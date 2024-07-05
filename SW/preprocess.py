from data.ncars import NCars
from data.mnistdvs import MnistDVS
from data.cifar10 import Cifar10

import argparse
import multiprocessing as mp


def main(args):

    if args.dataset == 'mnistdvs':
        dm = MnistDVS(data_dir='dataset', batch_size=1, radius=args.radius)
    elif args.dataset == 'ncars':
        dm = NCars(data_dir='dataset', batch_size=1, radius=args.radius)
    elif args.dataset == 'cifar10':
        dm = Cifar10(data_dir='dataset', batch_size=1, radius=args.radius)
    else:
        raise ValueError(f'Dataset {args.dataset} not supported')
    dm.prepare_data()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dataset', type=str, default='ncars')
    parser.add_argument('--radius', type=int, default=3)

    args = parser.parse_args()
    mp.set_start_method('spawn', force=True)
    main(args)