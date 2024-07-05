import torch
import torch.nn as nn
import torch.nn.functional as F

from networks.layers.utils.observer import Observer, FakeQuantize
from networks.layers.utils.quantize import quantize_tensor, dequantize_tensor

class QuantReLU(nn.Module):
    '''Quantized version of ReLU layer.'''
    def __init__(self, 
                 num_bits:int = 8):
        super().__init__()
        
        self.num_bits = num_bits

        '''Initialize quantization observers for input tensors.'''
        self.observer_in = Observer(num_bits=num_bits)

    def forward(self, 
                features: torch.Tensor):

        '''Standard ReLU forward pass.'''
        return F.relu(features)
    
    def calibration(self, 
                    features: torch.Tensor,
                    use_obs: bool = False):
        
        '''Calibration forward for updating observers.'''
        if use_obs:
            '''Update input observer.'''
            self.observer_in.update(features)
            features = FakeQuantize.apply(features, self.observer_in)

        features = F.relu(features)
        return features


    def freeze(self,
               observer_in: Observer = None):
        
        '''Freeze model - quantize weights/bias and calculate scales'''
        if observer_in is not None:
            self.observer_in = observer_in

    def q_forward(self, 
                  features: torch.Tensor):
        
        '''Quantized forward pass of ReLU layer.'''
        features = features.clone()
        features[features < self.observer_in.zero_point] = self.observer_in.zero_point
        return features


    def __repr__(self):
        return f"{self.__class__.__name__}, num_bits={self.num_bits})"
