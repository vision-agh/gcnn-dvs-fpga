import torch
import torch.nn as nn
import lightning as L
from torchmetrics import Accuracy
from tqdm import tqdm



def float_inference(model: nn.Module, 
                    dm: L.LightningDataModule,
                    device: str = 'cuda'):
    
    accuracy = Accuracy(task='multiclass', num_classes=dm.num_classes)

    preds = []
    y_true = []
    for idx, batch in tqdm(enumerate(dm.test_dataloader())):
        nodes = batch['nodes'].to(device)
        features = batch['features'].to(device)
        edges = batch['edges'].to(device)
        pred = model(nodes, features, edges) # Float forward pass
        y_pred = torch.argmax(pred, dim=-1)
        preds.append(y_pred.cpu().unsqueeze(0))
        y_true.append(batch['y'])

    preds = torch.cat(preds, dim=0).to('cpu')
    y_true = torch.tensor(y_true).to('cpu')

    print("\nAccuracy for float model on test dataset:", accuracy(preds, y_true).item())


def calibration_inference(model, 
                          dm: L.LightningDataModule,
                          num_calibration_samples: int = 500,
                          device: str = 'cuda'):
    
    for idx, batch in enumerate(dm.train_dataloader()):
        nodes = batch['nodes'].to(device)
        features = batch['features'].to(device)
        edges = batch['edges'].to(device)
        _ = model.calibration(nodes, features, edges)
        if idx > num_calibration_samples:
            break
    return model

def quantize_inference(model: nn.Module, 
                    dm: L.LightningDataModule,
                    device: str = 'cuda'):

    accuracy = Accuracy(task='multiclass', num_classes=dm.num_classes)
    preds = []
    y_true = []
    for idx, batch in tqdm(enumerate(dm.test_dataloader())):
        nodes = batch['nodes'].to(device)
        features = batch['features'].to(device)
        edges = batch['edges'].to(device)
        pred = model.q_forward(nodes, features, edges)
        y_pred = torch.argmax(pred, dim=-1)
        preds.append(y_pred.cpu().unsqueeze(0))
        y_true.append(batch['y'])
    
    preds = torch.cat(preds, dim=0).to('cpu')
    y_true = torch.tensor(y_true).to('cpu')

    print("\nAccuracy for quantised model on test dataset:", accuracy(preds, y_true).item())
