import torch
import torch.nn as nn
from torch.autograd import Function

from networks.layers.utils.quantize import quantize_tensor, dequantize_tensor
'''This code is based on the following repository:'''
'''https://github.com/Jermmy/pytorch-quantization-demo'''

class Observer(nn.Module):
    def __init__(self, 
                 num_bits:int = 8):
        super().__init__()

        self.num_bits = num_bits

        '''Initialize parameters for quantization'''
        scale = torch.tensor([], requires_grad=False)
        zero_point = torch.tensor([], requires_grad=False)
        min = torch.tensor([], requires_grad=False)
        max = torch.tensor([], requires_grad=False)
        self.register_buffer('scale', scale)
        self.register_buffer('zero_point', zero_point)
        self.register_buffer('min', min)
        self.register_buffer('max', max)

    def update(self, tensor: torch.Tensor):
        
        '''Update parameters for quantization'''
        if self.max.nelement() == 0 or self.max < tensor.max():
            self.max = tensor.max()
        self.max.clamp_(min=0)

        if self.min.nelement() == 0 or self.min > tensor.min():
            self.min = tensor.min()
        self.min.clamp_(max=0)

        self.scale, self.zero_point = self.calcScaleZeroPoint()

    def quantize_tensor(self, tensor: torch.Tensor):
        
        '''Quantize tensor'''
        return quantize_tensor(tensor, self.scale, self.zero_point, self.num_bits)
    
    def dequantize_tensor(self, tensor_quant: torch.Tensor):
        
        '''Dequantize tensor'''
        return dequantize_tensor(tensor_quant, self.scale, self.zero_point)

    def calcScaleZeroPoint(self):

        '''Calculate scale and zero point for quantization'''
        qmin = 0.
        qmax = 2. ** self.num_bits - 1.
        scale = (self.max - self.min) / (qmax - qmin)

        zero_point = qmax - self.max / scale

        if zero_point < qmin:
            zero_point = torch.tensor([qmin], dtype=torch.float32).to(self.min.device)
        elif zero_point > qmax:
            zero_point = torch.tensor([qmax], dtype=torch.float32).to(self.max.device)
        
        zero_point = zero_point.round()
        return scale, zero_point
    

class FakeQuantize(Function):
    '''Function for fake quantization.'''
    '''This function is used to calculate loss that occurs due to quantization.'''
    @staticmethod
    def forward(ctx, x, qparam):
        x = qparam.quantize_tensor(x)
        x = qparam.dequantize_tensor(x)
        return x

    @staticmethod
    def backward(ctx, grad_output):
        return grad_output, None