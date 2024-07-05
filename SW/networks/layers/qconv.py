import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.autograd import Variable

from networks.layers.utils.observer import Observer, FakeQuantize
from networks.layers.utils.quantize import quantize_tensor, dequantize_tensor

class QuantGraphConv(nn.Module):
    '''Quantized version of GraphConv layer.'''
    def __init__(self, 
                 input_dim: int = 1, 
                 output_dim: int = 4,
                 bias:bool = False,
                 num_bits:int = 8):
        super().__init__()
        
        '''Initialize standard layers.'''
        self.input_dim = input_dim
        self.output_dim = output_dim
        self.bias = bias

        self.linear = nn.Linear(input_dim + 3, output_dim, bias=bias)
        # self.global_nn = nn.Linear(output_dim, output_dim, bias=bias) # TODO - for global_nn

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
                node: torch.Tensor, 
                features: torch.Tensor, 
                edges: torch.Tensor):
        
        '''Standard forward pass of GraphConv layer.'''

        '''Calculate message for PointNet layer.'''
        pos_i = node[edges[:, 0]]
        pos_j = node[edges[:, 1]]
        x_j = features[edges[:, 1]]
        msg = torch.cat((x_j, pos_j - pos_i), dim=1)

        '''Propagate message through linear layer.'''
        msg = self.linear(msg)

        '''Update graph features.'''
        unique_positions, indices = torch.unique(edges[:,0], dim=0, return_inverse=True)
        expanded_indices = indices.unsqueeze(1).expand(-1, self.output_dim)
        pooled_features = torch.zeros((unique_positions.size(0), self.output_dim), dtype=features.dtype, device=features.device)
        pooled_features = pooled_features.scatter_reduce(0, expanded_indices, msg, reduce="amax", include_self=False)

        return pooled_features
    
    def calibration(self, 
                    node: torch.Tensor, 
                    features: torch.Tensor, 
                    edges: torch.Tensor,
                    use_obs: bool = False):
        
        '''Calibration forward for updating observers.'''        
        '''Calculate message for PointNet layer.'''
        pos_i = node[edges[:, 0]]
        pos_j = node[edges[:, 1]]
        x_j = features[edges[:, 1]]
        msg = torch.cat((x_j, pos_j - pos_i), dim=1)

        if use_obs:
            '''Update input observer.'''
            self.observer_in.update(msg)
            msg = FakeQuantize.apply(msg, self.observer_in)

        '''Update batch normalization observer.'''

        '''Update weight observer and propagate message through linear layer.'''
        self.observer_w.update(self.linear.weight)

        msg = F.linear(msg, FakeQuantize.apply(self.linear.weight, self.observer_w), self.linear.bias) # Merge batch normalization will always have bias

        '''Update output observer and calculate output.'''
        '''We calibrate based on the output of the Linear and also for diff POS for next layer'''
        self.observer_out.update(msg)
        self.observer_out.update(pos_j-pos_i)
        msg = FakeQuantize.apply(msg, self.observer_out)

        '''Update graph features.'''
        unique_positions, indices = torch.unique(edges[:,0], dim=0, return_inverse=True)
        expanded_indices = indices.unsqueeze(1).expand(-1, self.output_dim)
        pooled_features = torch.zeros((unique_positions.size(0), self.output_dim), dtype=features.dtype, device=features.device)
        pooled_features = pooled_features.scatter_reduce(0, expanded_indices, msg, reduce="amax", include_self=False)
        
        return pooled_features


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



        with torch.no_grad():
            self.linear.weight = torch.nn.Parameter(self.observer_w.quantize_tensor(self.linear.weight))
            self.linear.weight = torch.nn.Parameter(self.linear.weight - self.observer_w.zero_point)

            self.linear.bias = torch.nn.Parameter(quantize_tensor(self.linear.bias, scale=self.observer_in.scale*self.observer_w.scale,
                                            zero_point=0,
                                            num_bits=32,
                                            signed=True))

    def q_forward(self, 
                  node: torch.Tensor, 
                  features: torch.Tensor, 
                  edges: torch.Tensor,
                  first_layer: bool = False,
                  after_pool: bool = False):
        
        '''Quantized forward pass of GraphConv layer.'''

        '''Quantize input features'''
        if first_layer:
            '''We need to quantize both features and POS for the first layer.'''
            pos_i = node[edges[:, 0]]
            pos_j = node[edges[:, 1]]
            x_j = features[edges[:, 1]]
            msg = torch.cat((x_j, pos_j - pos_i), dim=1)
            msg = self.observer_in.quantize_tensor(msg)
        else:
            '''For other layers, we only quantize POS, because features are already quantized.'''
            pos_i = node[edges[:, 0]]
            pos_j = node[edges[:, 1]]
            pos = self.observer_in.quantize_tensor(pos_j - pos_i)
            msg = torch.cat((features[edges[:, 1]], pos), dim=1)

        msg = msg - self.observer_in.zero_point
        msg = self.linear(msg)
        msg = (msg * self.m + self.observer_out.zero_point).floor() 
        msg = torch.clamp(msg, 0, 2**self.num_bits - 1)

        '''Update graph features.'''
        unique_positions, indices = torch.unique(edges[:,0], dim=0, return_inverse=True)
        expanded_indices = indices.unsqueeze(1).expand(-1, self.output_dim)
        pooled_features = torch.zeros((unique_positions.size(0), self.output_dim), dtype=features.dtype, device=features.device)
        pooled_features = pooled_features.scatter_reduce(0, expanded_indices, msg, reduce="amax", include_self=False) # Find max features for each node
        
        return pooled_features

    def __repr__(self):
        return f"{self.__class__.__name__}(input_dim={self.input_dim}, output_dim={self.output_dim}, bias={self.bias}, num_bits={self.num_bits})"
