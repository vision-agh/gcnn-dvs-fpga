# Software part of the project

This repository contains code for the software part of the project. It contains the implementation of each layers of the Graph Convolutional Neural Network (GCNN) written in PyTorch. 

## Installation

To start the project, you need to install all dependencies:

```sh
conda create -n gnn python=3.9
conda activate gnn
conda install pytorch torchvision torchaudio pytorch-cuda=11.8 -c pytorch -c nvidia
pip install lightning tqdm
```

## Getting Started

You can run the evaluation of models for three datasets: N-Cars, MNIST-DVS, and CIFAR10-DVS.

To download trained float and quantized models, go to this [link](https://drive.google.com/drive/folders/1HT8CVoXCRX6az-eNrg5snilBBYpU-10D?usp=sharing). 
You can also download the processed and original datasets from this link.

The original datasets can be downloaded from the following links:

- [N-Cars](https://www.prophesee.ai/2018/03/13/dataset-n-cars/)
- [MNIST-DVS](http://www2.imse-cnm.csic.es/caviar/MNISTDVS.html)
- [CIFAR10-DVS](https://figshare.com/articles/dataset/CIFAR10-DVS_New/4724671/2)

## Folder Structure
After downloading the datasets and models, the folder structure should look like this:

```
dataset
  ├── ncars
  │   ├── processed_3
  │   │   ├── train     
  │   │   └── test
  │   └── processed_5     
  │       ├── train     
  │       └── test
  ├── cifar10-dvs
  │   ├── processed_3
  │   │   ├── train     
  │   │   └── test
  │   └── processed_5     
  │       ├── train     
  │       └── test
  └── mnist-dvs
      ├── processed_3
      │   ├── train     
      │   └── test
      └── processed_5     
          ├── train     
          └── test
weights
  ├── ncars
  │   ├── float_model_3.ckpt
  │   ├── qat_model_3.ckpt
  │   ├── float_model_5.ckpt
  │   └── qat_model_5.ckpt
  ├── cifar10-dvs
  │   └── ...
  └── mnist-dvs
      └── ...
```

##  Running

To preprocess the datasets, run the following command:

```sh
python preprocess.py --dataset ncars/mnistdvs/cifar10 --radius 3/5
```
*Note that processing the datasets can take a long time, so it is recommended to download the processed datasets.*

To evaluate the model for float and quantized models, run the following command:

```sh
python evaluate.py --dataset ncars/mnistdvs/cifar10 --radius 3/5
```

