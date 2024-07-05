import torch
import torch.nn as nn


def load_ckpt_model(model: nn.Module, 
                    checkpoint: str):
    
    '''Load model from checkpoint'''
    checkpoint = torch.load(checkpoint, map_location=torch.device('cuda'))

    print("\nUpdating model parameters...")
    '''Load model from checkpoint'''
    new_state_dict = {}
    for k, v in checkpoint['state_dict'].items():
        name = k[6:]
        new_state_dict[name] = v

    '''Update convolutional layers'''
    for k in model.state_dict().keys():
        if k in new_state_dict.keys(): 
            print("Updating parameters:", k)
            model.state_dict()[k].copy_(new_state_dict[k])

            '''Update linear layers'''
        elif k[0:7] == 'linear.':
            if k[7:] in new_state_dict.keys():
                print("Updating parameters:", k)
                model.state_dict()[k].copy_(new_state_dict[k[7:]])

    return model