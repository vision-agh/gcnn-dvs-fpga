import os
import glob
import numpy as np
import torch
import lightning as L

from tqdm import tqdm
from tqdm.contrib.concurrent import process_map
from torch.utils.data import DataLoader

from networks.layers.graph_gen import GraphGen
from utils.normalise import normalise
from data.base.event_ds import EventDS

device = torch.device(torch.cuda.current_device()) if torch.cuda.is_available() else torch.device('cpu')

class NCars(L.LightningDataModule):
    def __init__(self, 
                 data_dir, 
                 batch_size,
                 radius=3):
        super().__init__()

        # Dataset directory and name.
        self.data_dir = data_dir
        self.data_name = 'ncars'

        # Initialize train and test dataset.
        self.train_data = None
        self.test_data = None

        # Time window, normalization dimension and radius for graph generation.
        self.time_window = 0.1 # 100 ms
        self.original_dim = (120, 100, self.time_window)
        self.dim = (128, 128, 128)
        self.radius = radius

        # Number of workers, batch size and processes for data preparation.
        self.num_workers = 2
        self.batch_size = batch_size
        self.processes = 6

        # Number of classes and class dictionary.
        self.num_classes = 2
        self.class_dict = {'background': 0, 'car': 1}

    ############################################################################
    # SINGLE FILE PROCESSING ###################################################
    ############################################################################

    def process_file(self, data_file) -> None:   
        # Create name for processed file.
        processed_file = data_file.replace(self.data_name, self.data_name + '/processed' + f'_{self.radius}').replace('txt', 'pt')

        # Check if processed file already exists.
        if os.path.exists(processed_file):
            return

        # Create directory for processed file.
        os.makedirs(os.path.dirname(processed_file), exist_ok=True)

        # Extract events from raw data file.
        events_file = os.path.join(data_file)
        events = np.loadtxt(events_file)

        all_x = events[:, 0]
        all_y = events[:, 1]
        all_ts = events[:, 2]
        all_p = events[:, 3]
        all_p[all_p == 0] = -1
        
        events = {}
        events['x'] = all_x
        events['y'] = all_y
        events['t'] = all_ts.astype(np.float64)
        events['p'] = all_p
        
        # Filter events by time window.
        mask = (events['t'] < self.time_window)
        events['x'] = events['x'][mask]
        events['y'] = events['y'][mask]
        events['t'] = events['t'][mask]
        events['p'] = events['p'][mask]

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
        y = np.loadtxt(data_file.replace('events.txt', 'is_car.txt')).astype(np.int32)
        data = {'nodes': nodes.to("cpu"), 
                'features': features.to("cpu"), 
                'edges': edges.to("cpu"), 
                'y': y.item()}

        # Save processed file
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
        data_files = glob.glob(os.path.join(self.data_dir, self.data_name, mode, '*', 'events.txt'))
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
        return DataLoader(self.test_data, batch_size=self.batch_size, num_workers=self.num_workers, shuffle=False, collate_fn=self.collate_fn, persistent_workers=False)
    
    def test_dataloader(self):
        return DataLoader(self.test_data, batch_size=self.batch_size, num_workers=self.num_workers, shuffle=False, collate_fn=self.collate_fn, persistent_workers=False)
    
    def collate_fn(self, data_list):
        # To work with batched data, we should change this function.
        return data_list[0]