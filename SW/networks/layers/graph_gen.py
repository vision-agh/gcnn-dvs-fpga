import torch
from torch.nn import Module


class GraphGen(Module):
    def __init__(self, r, dimension_XY=256, self_loop=True):
        super(GraphGen, self).__init__()
        # Module parameters
        self.r = r
        self.dimension_XY = dimension_XY

        # Gemerate neighbour matrix
        self.neighbour_matrix = torch.zeros((dimension_XY, dimension_XY), dtype=torch.int32)
        
        # Precompute context ranges 
        self.precomputed_ctx_ranges = {i: torch.arange(max(0, i - self.r), min(self.dimension_XY, i + self.r + 1)) for i in range(self.dimension_XY)}
        
        # Initialize lists
        self.pos = []
        self.features = []
        self.edges = []

        # Initialize index of the last added node
        self.index = -1

        # Self loop
        self.self_loop = self_loop

    def forward(self, event):
        # Unpack event
        x = event[0]
        y = event[1]
        t = event[2]
        feature = event[3]
        # Check if the event is a duplicate
        if self._check_duplicate(x, y, t):
            self.index += 1
            self._generate_edges(x, y, t)
            self.pos.append([x, y, t])
            self.features.append([feature])
            self.neighbour_matrix[x, y] = self.index

    def _check_duplicate(self, x, y, t):
        return False if self.neighbour_matrix[x, y] != 0 and self.pos[self.neighbour_matrix[x, y]][2] == t else True
        
    def _generate_edges(self, x, y, t):
        # Generate indices of context
        x_ctx_range = self.precomputed_ctx_ranges[x]
        y_ctx_range = self.precomputed_ctx_ranges[y]
        x_ctx, y_ctx = torch.meshgrid(x_ctx_range, y_ctx_range, indexing='ij')
        x_ctx, y_ctx = x_ctx.flatten(), y_ctx.flatten()

        # Add self loop
        if self.self_loop:
            self.edges.append((self.index, self.index))

        # Get indices of context from the neighbour matrix
        context = self.neighbour_matrix[x_ctx, y_ctx]
        idxes = context[context != 0]

        # Check if the potential neighbour is in the context and add edge
        for idx in idxes:
            x_ctx, y_ctx, t_ctx = self.pos[idx][:3]
            square_distance = (x_ctx - x) ** 2 + (y_ctx - y) ** 2 + (t_ctx - t) ** 2
            if square_distance <= self.r ** 2:
                self.edges.append((self.index, idx))

    def release(self):
        # Convert lists to tensors
        nodes_tensor = torch.tensor(self.pos, dtype=torch.float32, device='cpu')
        features_tensor = torch.tensor(self.features, dtype=torch.float32, device='cpu')
        edges_tensor = torch.tensor(self.edges, dtype=torch.int32, device='cpu')

        # Clear lists
        self.pos = []
        self.features = []
        self.edges = []
        self.index = -1

        return nodes_tensor, features_tensor, edges_tensor

    def __repr__(self):
        return f"{self.__class__.__name__}(dimension_size={self.dimension_XY})(radius={self.r})"