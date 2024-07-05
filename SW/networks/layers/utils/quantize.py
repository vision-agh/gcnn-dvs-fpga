import torch

def quantize_tensor(tensor: torch.Tensor,
                    scale: torch.Tensor,
                    zero_point: torch.Tensor,
                    num_bits: int = 8,
                    signed: bool = False):
        
        '''Quantize tensor'''
        if signed:
                qmin = - 2. ** (num_bits - 1)
                qmax = 2. ** (num_bits - 1) - 1
        else:
                qmin = 0.
                qmax = 2. ** num_bits - 1.

        q_x = zero_point + (tensor / scale)
        q_x = q_x.round()
        q_x.clamp(qmin, qmax)
        
        return q_x
    
def dequantize_tensor(tensor_quant: torch.Tensor,
                      scale: torch.Tensor,
                      zero_point: torch.Tensor):
    
    '''Dequantize tensor'''
    return scale * (tensor_quant - zero_point)