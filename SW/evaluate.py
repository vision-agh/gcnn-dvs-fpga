import torch
import numpy as np
import os
import argparse

from data.ncars import NCars
from data.mnistdvs import MnistDVS
from data.cifar10 import Cifar10

from networks.efgcn import EFGCN

from utils.run_models import float_inference, quantize_inference, calibration_inference
from utils.load_ckpt_model import load_ckpt_model

def parse_args():
    parser = argparse.ArgumentParser(description='Train a model')
    parser.add_argument('--dataset', type=str, default='cifar10', help='Dataset to use')
    parser.add_argument('--radius', type=int, default=5, help='Radius of the graph')
    return parser.parse_args()

def main(args):
    folder_name = 'weights/' + args.dataset
    
    if args.dataset == 'ncars':
        dm = NCars(data_dir='dataset', batch_size=1, radius=args.radius)
    elif args.dataset == 'cifar10':
        dm = Cifar10(data_dir='dataset', batch_size=1, radius=args.radius)
    elif args.dataset == 'mnistdvs':
        dm = MnistDVS(data_dir='dataset', batch_size=1, radius=args.radius)
    else:
        raise ValueError('Dataset not supported')
    dm.setup()

    model = EFGCN(input_dimension=dm.dim, num_outputs=dm.num_classes, num_bits=8, bias=True).cuda()
    model.eval()

    # Load the float model
    model.load_state_dict(torch.load(folder_name+f'/float_model_{args.radius}.ckpt', map_location='cuda'))

    # Run the float model
    float_inference(model=model, dm=dm, device='cuda')

    # Run calibration only for initialisation all parameters
    model = calibration_inference(model=model, dm=dm, num_calibration_samples=1, device='cuda')
    model.freeze()

    # Load the quantized model
    param = torch.load(folder_name+f'/qat_model_{args.radius}.ckpt', map_location='cuda')
    for pa in param:
        model.state_dict()[pa].copy_(param[pa])

    # Run the quantized model
    quantize_inference(model=model, dm=dm, device='cuda')

if __name__ == '__main__':
    args = parse_args()
    main(args)
