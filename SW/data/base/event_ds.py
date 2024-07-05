import torch
from torch.utils.data import Dataset

class EventDS(Dataset):
    def __init__(self, files, dim=256, augmentations=None):
        self.files = files
        self.dim = dim


    def __len__(self) -> int:
        return len(self.files)
    
    def __getitem__(self, index: int):
        data_file = self.files[index]
        data = torch.load(data_file)
        return data