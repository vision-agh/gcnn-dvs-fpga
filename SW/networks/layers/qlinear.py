import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from networks.layers.utils.observer import Observer, FakeQuantize
from networks.layers.utils.quantize import quantize_tensor, dequantize_tensor

class QuantLinear(nn.Module):
    '''Quantized version of Linear layer.'''
    def __init__(self, 
                 input_dim: int = 1, 
                 output_dim: int = 4,
                 bias:bool = True,
                 num_bits:int = 8):
        super().__init__()
        
        '''Initialize standard layers.'''
        self.input_dim = input_dim
        self.output_dim = output_dim
        self.bias = bias

        self.linear = nn.Linear(input_dim, output_dim, bias=bias)

        self.num_bits = num_bits

        '''Initialize quantization observers for input, weight and output tensors.'''
        self.observer_in = Observer(num_bits=num_bits)
        self.observer_w = Observer(num_bits=num_bits)
        self.observer_out = Observer(num_bits=num_bits)
        self.register_buffer('m', torch.tensor([-1], requires_grad=False))
        
        '''Initialize quantized version of scales.'''
        self.register_buffer('qscale_in', torch.tensor([-1], requires_grad=False))
        self.register_buffer('qscale_w', torch.tensor([-1], requires_grad=False))
        self.register_buffer('qscale_out', torch.tensor([-1], requires_grad=False))
        self.register_buffer('qscale_m', torch.tensor([-1], requires_grad=False))

        '''Initialize numbers of bits for model quantization and scales.'''
        self.register_buffer('num_bits_model', torch.tensor([num_bits], requires_grad=False))
        self.register_buffer('num_bits_scale', torch.tensor([-1], requires_grad=False))

    def forward(self, 
                features: torch.Tensor):

        '''Standard forward pass of Linear layer.'''
        return self.linear(features)
    
    def calibration(self, 
                    features: torch.Tensor,
                    use_obs: bool = False):
        
        '''Calibration forward for updating observers.'''
        if use_obs:
            '''Update input observer.'''
            self.observer_in.update(features)
            features = FakeQuantize.apply(features, self.observer_in)

        '''Update weight observer and propagate message through linear layer.'''
        self.observer_w.update(self.linear.weight.data)

        if self.bias:
            features = F.linear(features, FakeQuantize.apply(self.linear.weight, self.observer_w), self.linear.bias)
        else:
            features = F.linear(features, FakeQuantize.apply(self.linear.weight, self.observer_w))
        
        '''Update output observer and calculate output.'''
        self.observer_out.update(features)
        features = FakeQuantize.apply(features, self.observer_out)
        return features


    def freeze(self,
               observer_in: Observer = None,
               observer_out: Observer = None,
               num_bits: int = 32):
        
        '''Freeze model - quantize weights/bias and calculate scales'''
        if observer_in is not None:
            self.observer_in = observer_in
        if observer_out is not None:
            self.observer_out = observer_out

        self.num_bits_scale = torch.tensor([num_bits], requires_grad=False)

        scale_in = (2**num_bits-1) * self.observer_in.scale
        self.qscale_in = scale_in.round()
        self.observer_in.scale = scale_in.round() / (2**num_bits-1)

        scale_w = (2**num_bits-1) * self.observer_w.scale
        self.qscale_w = scale_w.round()
        self.observer_w.scale = scale_w.round() / (2**num_bits-1)

        scale_out = (2**num_bits-1) * self.observer_out.scale
        self.qscale_out = scale_out.round()
        self.observer_out.scale = scale_out.round() / (2**num_bits-1)

        m = (self.observer_w.scale * self.observer_in.scale / self.observer_out.scale)
        m = (2**num_bits-1) * m
        self.qscale_m = m.round()
        self.m = m.round() / (2**num_bits-1)
            
        self.linear.weight = torch.nn.Parameter(self.observer_w.quantize_tensor(self.linear.weight))
        self.linear.weight = torch.nn.Parameter(self.linear.weight - self.observer_w.zero_point)

        if self.bias:
            self.linear.bias = torch.nn.Parameter(quantize_tensor(self.linear.bias, 
                                        scale=self.observer_in.scale * self.observer_w.scale,
                                        zero_point=0, 
                                        num_bits=32, 
                                        signed=True))

    def q_forward(self, 
                  features: torch.Tensor, 
                  first_layer: bool = False):
        
        '''Quantized forward pass of Linear layer.'''
        
        '''Quantize input features'''
        if first_layer:
            '''We need to quantize features.'''
            features = self.observer_in.quantize_tensor(features)
            features = features - self.observer_in.zero_point
        else:
            '''For other layers, we do not need to quantize features'''
            features = features - self.observer_in.zero_point
        features = self.linear(features)
        features = (features * self.m + self.observer_out.zero_point).round()
        features = torch.clamp(features, 0, 2**self.num_bits - 1)
        return features

    def __repr__(self):
        return f"{self.__class__.__name__}(input_dim={self.input_dim}, output_dim={self.output_dim}, bias={self.bias}, num_bits={self.num_bits})"
