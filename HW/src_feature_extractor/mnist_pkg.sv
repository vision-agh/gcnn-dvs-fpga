package graph_pkg;

    //////////////////////////////
    // CONFIGURATION PARAMETERS //
    //////////////////////////////

    parameter GRAPH_SIZE       = 128;                  // The size of graph representation (in x, y and time dimensions)
    parameter GRAPH_BIT_WIDTH  = $clog2(GRAPH_SIZE);
    parameter RADIUS           = 3;                    // The search radius for egde generation
    parameter MAX_EDGES	       = 29;                   // The maximum number of edges for single vertice (before graph rescaling - MaxPool)
    parameter TIME_WINDOW      = 200000;               // The time window for events accumulation for single graph representation (in us)
    parameter PRECISION        = 8;                    // Precision for weights and features in GCNN model (in bits)
    parameter string REPO_PATH = "/path/to/repo";      // Path to repository (needed for memory init files)
    
    ////////////////
    // DATA TYPES //
    ////////////////

    // event_type for normalized events processing
    typedef struct packed {
      logic [GRAPH_BIT_WIDTH-1 : 0] x;
      logic [GRAPH_BIT_WIDTH-1 : 0] y;
      logic [GRAPH_BIT_WIDTH-1 : 0] t;
      logic	                        p;
      logic                         valid;
    } event_type;
    
    // edge_type for processing egde list (before graph rescaling - MaxPool)
    typedef struct packed {
      logic [$clog2(RADIUS) : 0] t;
      logic                      attribute;
      logic                      is_connected;
    } edge_type;

    ///////////////////////////////
    // CONTEXT MEMORY PARAMETERS //
    ///////////////////////////////

    parameter MEMORY_OPS_NUM = 15;   // Number of memory accesses for single event (before graph rescaling - MaxPool)
    parameter MEMORY_OPS_NUM_MP = 5; // Number of memory accesses for single event (after graph rescaling - MaxPool)

    // Consecutive relative addresses for memory accesses (before graph rescaling - MaxPool)
    parameter logic [1:0] MEM_ADDR_A_X [MEMORY_OPS_NUM-1:0] = {0, 1, 2, 3, 2, 1, 0, 1, 2, 2, 1, 0, 1, 2, 0};  //LAST IS WRITE
    parameter bit         MEM_SIGN_A_X [MEMORY_OPS_NUM-1:0] = {0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0};

    parameter logic [1:0] MEM_ADDR_B_X [MEMORY_OPS_NUM-1:0] = {0, 2, 1, 0, 1, 2, 2, 1, 0, 1, 2, 3, 2, 1, 0};
    parameter bit         MEM_SIGN_B_X [MEMORY_OPS_NUM-1:0] = {0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0};
    
    parameter logic [1:0] MEM_ADDR_B_Y [MEMORY_OPS_NUM-1:0] = {3, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 0, 0}; //[Always positive]
    parameter logic [1:0] MEM_ADDR_A_Y [MEMORY_OPS_NUM-1:0] = {0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3}; //[Always negative] LAST IS WRITE

endpackage;