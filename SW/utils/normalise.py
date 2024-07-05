import numpy as np

def normalise(events, original, normalised):
    '''Normalise events to norm_value.'''
    
    x = (events['x']*normalised[0]/original[0])
    y = (events['y']*normalised[1]/original[1])
    t = events['t']
    p = events['p']
    
    t = t / original[2]
    t = (t * normalised[2])
    
    events = np.column_stack((x, y, t, p))
    return events.astype(np.int32)