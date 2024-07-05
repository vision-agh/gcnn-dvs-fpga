import numpy as np
import torch
from torch.nn import Module
from networks.layers.qconv import QuantGraphConv
from networks.layers.qpool_out import QuantGraphPoolOut
from networks.layers.qlinear import QuantLinear
from networks.layers.qrelu import QuantReLU
from networks.layers.max_pool import GraphPooling
    
class EFGCN(Module):
    def __init__(self, 
                 input_dimension = (256, 256, 256),
                 bias: bool = False, 
                 num_outputs: int = 100, 
                 num_bits: int = 8):
        super(EFGCN, self).__init__()

        self.conv1 = QuantGraphConv(input_dim=1, output_dim=16, bias=bias, num_bits=num_bits)
        self.relu1 = QuantReLU(num_bits=num_bits)

        self.max_pool1 = GraphPooling(pool_size=4, max_dimension=input_dimension[0], only_vertices=False, self_loop=True)

        self.conv2 = QuantGraphConv(input_dim=16, output_dim=32, bias=bias, num_bits=num_bits)
        self.relu2 = QuantReLU(num_bits=num_bits)
        self.conv3 = QuantGraphConv(input_dim=32, output_dim=32, bias=bias, num_bits=num_bits)
        self.relu3 = QuantReLU(num_bits=num_bits)

        self.max_pool2 = GraphPooling(pool_size=2, max_dimension=input_dimension[0]//4, only_vertices=False, self_loop=True)

        self.conv4 = QuantGraphConv(input_dim=32, output_dim=64, bias=bias, num_bits=num_bits)
        self.relu4 = QuantReLU(num_bits=num_bits)
        self.conv5 = QuantGraphConv(input_dim=64, output_dim=64, bias=bias, num_bits=num_bits)
        self.relu5 = QuantReLU(num_bits=num_bits)

        out_pull = 8 if input_dimension[0]==256 else 4

        self.out = QuantGraphPoolOut(pool_size=out_pull, max_dimension=input_dimension[0]//8)
        self.linear = QuantLinear(4*4*4*64, num_outputs, bias=bias)

    def forward(self, nodes, features, edges):
        '''Standard forward method for training on floats'''
        features = self.conv1(nodes, features, edges)
        features = self.relu1(features)

        nodes, features, edges = self.max_pool1(nodes, features, edges)

        features = self.conv2(nodes, features, edges)
        features = self.relu2(features)
        features = self.conv3(nodes, features, edges)
        features = self.relu3(features)

        nodes, features, edges = self.max_pool2(nodes, features, edges)
        
        features = self.conv4(nodes, features, edges)
        features = self.relu4(features)
        features = self.conv5(nodes, features, edges)
        features = self.relu5(features)
        
        features = self.out(nodes, features)
        features = self.linear(features)
        return features
    
    def calibration(self, nodes, features, edges):
        '''Calibration method to adjust quantize parameters on dataset'''
        features = self.conv1.calibration(nodes, features, edges, use_obs=True)
        features = self.relu1.calibration(features)
        
        nodes, features, edges = self.max_pool1(nodes, features, edges)

        features = self.conv2.calibration(nodes, features, edges)
        features = self.relu2.calibration(features)

        features = self.conv3.calibration(nodes, features, edges)
        features = self.relu3.calibration(features)

        nodes, features, edges = self.max_pool2(nodes, features, edges)

        features = self.conv4.calibration(nodes, features, edges)
        features = self.relu4.calibration(features)

        features = self.conv5.calibration(nodes, features, edges)
        features = self.relu5.calibration(features)

        features = self.out.calibration(nodes, features)
        features = self.linear.calibration(features)
        return features
    
    def freeze(self):
        '''Freeze parameters after calibration'''
        self.conv1.freeze()
        self.relu1.freeze(observer_in=self.conv1.observer_out)

        self.conv2.freeze(observer_in=self.conv1.observer_out)
        self.relu2.freeze(observer_in=self.conv2.observer_out)

        self.conv3.freeze(observer_in=self.conv2.observer_out)
        self.relu3.freeze(observer_in=self.conv3.observer_out)

        self.conv4.freeze(observer_in=self.conv3.observer_out)
        self.relu4.freeze(observer_in=self.conv4.observer_out)

        self.conv5.freeze(observer_in=self.conv4.observer_out)
        self.relu5.freeze(observer_in=self.conv5.observer_out)

        self.out.freeze(observer_in=self.conv5.observer_out)
        self.linear.freeze(observer_in=self.conv5.observer_out)

    def q_forward(self, nodes, features, edges):
        '''Forward method for quantized model'''
        features = self.conv1.q_forward(nodes, features, edges, first_layer=True)
        features = self.relu1.q_forward(features)

        nodes, features, edges = self.max_pool1(nodes, features, edges)

        features = self.conv2.q_forward(nodes, features, edges)
        features = self.relu2.q_forward(features)
        features = self.conv3.q_forward(nodes, features, edges)
        features = self.relu3.q_forward(features)

        nodes, features, edges = self.max_pool2(nodes, features, edges)

        features = self.conv4.q_forward(nodes, features, edges)
        features = self.relu4.q_forward(features)
        features = self.conv5.q_forward(nodes, features, edges)
        features = self.relu5.q_forward(features)

        features = self.out.q_forward(nodes, features)
        features = self.linear.q_forward(features)
        features = self.linear.observer_out.dequantize_tensor(features)
    
        return features
    
    def get_parameters(self):
        self.conv1.get_parameters('tiny_conv1_param.txt')
        self.conv2.get_parameters('tiny_conv2_param.txt')
        self.conv3.get_parameters('tiny_conv3_param.txt')
        self.conv4.get_parameters('tiny_conv4_param.txt')
        self.conv5.get_parameters('tiny_conv5_param.txt')
        self.linear.get_parameters('tiny_linear_param.txt')