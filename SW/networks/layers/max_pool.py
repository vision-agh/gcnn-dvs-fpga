import torch
from torch.nn import Module

class GraphPooling(Module):
    def __init__(self, pool_size=4, max_dimension=256, only_vertices=False, self_loop=True):
        super(GraphPooling, self).__init__()
        self.pool_size = pool_size
        self.max_dimension = max_dimension
        self.grid_size = max_dimension // pool_size
        self.only_vertices = only_vertices
        self.self_loop = self_loop

        self.average_positions = False

    def forward(self, vertices, features, edges):
        # Reduce dimension of vertices to find indices with the same pool cells
        normalized_vertices = torch.div(vertices, self.pool_size, rounding_mode='floor').to(torch.int64)

        # Change vertices to original dimensions - OPTIONAL
        # normalized_vertices = normalized_vertices * self.pool_size
        
        # Find indices of unique positions
        unique_positions, indices = torch.unique(normalized_vertices, dim=0, return_inverse=True)

        # Find indices of unique spatial positions - OPTIONAL (comment out the line above and uncomment the line below)
        # unique_positions, indices = torch.unique(normalized_vertices[:,:2], dim=0, return_inverse=True)

        # Average positions for each unique position
        if self.average_positions:
            averaged_positions = torch.zeros((unique_positions.size(0), 3), dtype=vertices.dtype, device=vertices.device)
            unique_positions = averaged_positions.scatter_reduce(0, indices.unsqueeze(1).expand(-1,3), vertices, reduce="mean", include_self=False)

        # Aggregate features for each unique position - OPTIONAL use other reduce functions instead of "sum"
        pooled_features = torch.zeros((unique_positions.size(0), features.size(1)), dtype=features.dtype, device=features.device)
        pooled_features = pooled_features.scatter_reduce(0, indices.unsqueeze(1).expand(-1, features.size(1)), features, reduce="amax", include_self=False) #TODO Change to True

        # For potential pruning graph at the beginning - OPTIONAL
        if self.only_vertices:
            return unique_positions, pooled_features
        
        # Remove self loops (for filter out the same positions duplicates)
        edge_index = indices[edges]
        mask = edge_index[:, 0] != edge_index[:, 1]
        edge_index = edge_index[mask, :]

        edge_index = torch.unique(edge_index, dim=0)
        
        # Add self loops (to keep only one self loop for each unique position)
        if self.self_loop:
            edge_index = torch.cat((edge_index, torch.arange(unique_positions.size(0), device=edge_index.device).unsqueeze(1).expand(-1, 2)), dim=0)
        return unique_positions, pooled_features, edge_index
    
    def __repr__(self):
        return f"{self.__class__.__name__}(pool_size={self.pool_size}, max_dimension={self.max_dimension})"