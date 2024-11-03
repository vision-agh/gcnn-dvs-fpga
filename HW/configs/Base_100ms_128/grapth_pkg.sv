package graph_pkg;

    // CONFIGURATION PARAMETERS
    parameter GRAPH_SIZE      = 256;
    parameter RADIUS          = 3;
    parameter MAX_EDGES	      = 29;
    parameter TIME_WINDOW     = 50000;
    parameter GRAPH_BIT_WIDTH = $clog2(GRAPH_SIZE);
    parameter PRECISION       = 8;
    
    // TYPES
    typedef struct packed {
      logic [GRAPH_BIT_WIDTH-1 : 0] x;
      logic [GRAPH_BIT_WIDTH-1 : 0] y;
      logic [GRAPH_BIT_WIDTH-1 : 0] t;
      logic							p;
      logic                         valid;
    } event_type;
    
    typedef struct packed {
      logic [$clog2(RADIUS) : 0] t;
      logic						 attribute;
      logic                      is_connected;
    } edge_type;

    // Before MaxPool
    parameter MEMORY_OPS_NUM = 15;

    parameter logic [1:0] MEM_ADDR_A_X [MEMORY_OPS_NUM-1:0] = {0, 1, 2, 3, 2, 1, 0, 1, 2, 2, 1, 0, 1, 2, 0};  //LAST IS WRITE
    parameter bit         MEM_SIGN_A_X [MEMORY_OPS_NUM-1:0] = {0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0};

    parameter logic [1:0] MEM_ADDR_B_X [MEMORY_OPS_NUM-1:0] = {0, 2, 1, 0, 1, 2, 2, 1, 0, 1, 2, 3, 2, 1, 0};
    parameter bit         MEM_SIGN_B_X [MEMORY_OPS_NUM-1:0] = {0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0};
    
    parameter logic [1:0] MEM_ADDR_B_Y [MEMORY_OPS_NUM-1:0] = {3, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 0, 0}; //[Always positive]
    parameter logic [1:0] MEM_ADDR_A_Y [MEMORY_OPS_NUM-1:0] = {0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3}; //LAST IS WRITE [Always negative]

    // After MaxPool
    parameter MEMORY_OPS_NUM_MP = 5;

    

endpackage;