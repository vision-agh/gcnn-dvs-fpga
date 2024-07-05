import os
import glob
import numpy as np
import torch
import lightning as L

from tqdm.contrib.concurrent import process_map
from torch.utils.data import DataLoader

from networks.layers.graph_gen import GraphGen
from utils.normalise import normalise
from data.base.event_ds import EventDS

device = torch.device(torch.cuda.current_device()) if torch.cuda.is_available() else torch.device('cpu')

class MnistDVS(L.LightningDataModule):
    def __init__(self, 
                 data_dir, 
                 batch_size,
                 radius=3):
        super().__init__()

        # Dataset directory and name.
        self.data_dir = data_dir
        self.data_name = 'mnist-dvs'

        # Initialize train and test dataset.
        self.train_data = None
        self.test_data = None

        # Time window, original dimension, normalized dimension and radius.
        self.time_window = 100000  # 100 ms
        self.original_dim = (128, 128, self.time_window)
        self.dim = (128, 128, 128)
        self.radius = radius

        # Number of workers, batch size and processes for data preparation.
        self.num_workers = 2
        self.batch_size = batch_size
        self.processes = 6

        # Number of classes.
        self.num_classes = 10

    ############################################################################
    # SINGLE FILE PROCESSING ###################################################
    ############################################################################

    def process_file(self, data_file) -> None:   
        # Create name for processed file.
        processed_file = data_file.replace(self.data_name, self.data_name + '/processed' + f'_{self.radius}').replace('aedat', 'pt')

        # Check if processed file already exists.
        if os.path.exists(processed_file):
            return

        # Create directory for processed file.
        os.makedirs(os.path.dirname(processed_file), exist_ok=True)

        # Extract events from raw data file.
        with open(data_file, 'rb') as fp:
            t, x, y, p = load_events(fp,
                        x_mask=0xfE,
                        x_shift=1,
                        y_mask=0x7f00,
                        y_shift=8,
                        polarity_mask=1,
                        polarity_shift=None)

            events = {'t': t, 'x': 127 - y, 'y': 127 - x, 'p': 1 - p.astype(int)}
        
        # Filter events by time window.
        mask = events['t'] < self.time_window 
        events = {k: v[mask] for k, v in events.items()}

        # We normalize x, y and t to the self.dim.
        events = normalise(events, original=self.original_dim, normalised=self.dim)

        assert events[:,0].max() < self.dim[0]
        assert events[:,1].max() < self.dim[1]
        assert events[:,2].max() < self.dim[2]
        
        # Generate graph from events.
        # We assume that data is normalised to dim[0] for all dimensions.
        graph_generator = GraphGen(r=self.radius, dimension_XY=self.dim[0], self_loop=True).to(device)

        for event in events.astype(np.int32):
            graph_generator.forward(event)
        nodes, features, edges = graph_generator.release()
        
        # Save processed file.
        # To prevent memory issues, we save data to CPU.
        y = data_file.split('/')[-2]
        data = {'nodes': nodes.to("cpu"), 
                'features': features.to("cpu"), 
                'edges': edges.to("cpu"), 
                'y': y}
        
        torch.save(data, processed_file)

    ############################################################################
    # DATA PREPARATION #########################################################
    ############################################################################

    def prepare_data(self) -> None:
        print('Preparing data...')
        for mode in ['train', 'test']:
            print(f'Loading {mode} data')
            os.makedirs(os.path.join(self.data_dir, self.data_name, 'processed' + f'_{self.radius}', mode), exist_ok=True)
            self._prepare_data(mode)

    def _prepare_data(self, mode: str) -> None:
        data_files = glob.glob(os.path.join(self.data_dir, self.data_name, mode, '*', 'mnist_*.aedat'))
        process_map(self.process_file, data_files, max_workers=self.processes, chunksize=1, )
            
    def setup(self, stage=None):
        # Load training and testing data.
        self.train_data = self.generate_ds('train')
        self.test_data = self.generate_ds('test')

    def generate_ds(self, mode: str):
        processed_files = glob.glob(os.path.join(self.data_dir, self.data_name, 'processed' + f'_{self.radius}',  mode, '*', '*.pt'))
        return EventDS(processed_files, self.dim)

    def train_dataloader(self):
        return DataLoader(self.train_data, batch_size=self.batch_size, num_workers=self.num_workers, shuffle=True, collate_fn=self.collate_fn, persistent_workers=False)

    def val_dataloader(self):
        return DataLoader(self.val_data, batch_size=self.batch_size, num_workers=self.num_workers, shuffle=False, collate_fn=self.collate_fn, persistent_workers=False)

    def test_dataloader(self):
        return DataLoader(self.test_data, batch_size=self.batch_size, num_workers=self.num_workers, shuffle=False, collate_fn=self.collate_fn, persistent_workers=False)
    
    def collate_fn(self, data_list):
        # To work with batched data, we should change this function.
        return data_list[0]

############################################################################################################
# CIFAR10-DVS READER
############################################################################################################
    
EVT_DVS = 0  # DVS event type
EVT_APS = 1  # APS event

def read_bits(arr, mask=None, shift=None):
    if mask is not None:
        arr = arr & mask
    if shift is not None:
        arr = arr >> shift
    return arr


y_mask = 0x7FC00000
y_shift = 22

x_mask = 0x003FF000
x_shift = 12

polarity_mask = 0x800
polarity_shift = 11

valid_mask = 0x80000000
valid_shift = 31


def skip_header(fp):
    p = 0
    lt = fp.readline()
    ltd = lt.decode().strip()
    while ltd and ltd[0] == "#":
        p += len(lt)
        lt = fp.readline()
        try:
            ltd = lt.decode().strip()
        except UnicodeDecodeError:
            break
    return p


def load_raw_events(fp,
                    bytes_skip=0,
                    bytes_trim=0,
                    filter_dvs=False,
                    times_first=False):
    p = skip_header(fp)
    fp.seek(p + bytes_skip)
    data = fp.read()
    if bytes_trim > 0:
        data = data[:-bytes_trim]
    data = np.fromstring(data, dtype='>u4')
    if len(data) % 2 != 0:
        print(data[:20:2])
        print('---')
        print(data[1:21:2])
        raise ValueError('odd number of data elements')
    raw_addr = data[::2]
    timestamp = data[1::2]
    if times_first:
        timestamp, raw_addr = raw_addr, timestamp
    if filter_dvs:
        valid = read_bits(raw_addr, valid_mask, valid_shift) == EVT_DVS
        timestamp = timestamp[valid]
        raw_addr = raw_addr[valid]
    return timestamp, raw_addr


def parse_raw_address(addr,
                      x_mask=x_mask,
                      x_shift=x_shift,
                      y_mask=y_mask,
                      y_shift=y_shift,
                      polarity_mask=polarity_mask,
                      polarity_shift=polarity_shift):
    polarity = read_bits(addr, polarity_mask, polarity_shift).astype(np.bool_)
    x = read_bits(addr, x_mask, x_shift)
    y = read_bits(addr, y_mask, y_shift)
    return x, y, polarity


def load_events(
        fp,
        filter_dvs=False,
        **kwargs):
    timestamp, addr = load_raw_events(
        fp,
        filter_dvs=filter_dvs,
    )
    x, y, polarity = parse_raw_address(addr, **kwargs)
    return timestamp, x, y, polarity