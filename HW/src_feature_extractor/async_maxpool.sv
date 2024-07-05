module async_maxpool #(
    parameter int IN_GRAPH_SIZE	 = 128,
    parameter int OUT_GRAPH_SIZE = 32,
    parameter int PRECISION	     = graph_pkg::PRECISION,
    parameter int INPUT_DIM      = 16,
    parameter int ADDR_WIDTH     = $clog2(OUT_GRAPH_SIZE*OUT_GRAPH_SIZE),
    parameter int DATA_WIDTH     = (INPUT_DIM*PRECISION) + (9*2) //edges
)( 
    input logic                                             clk,
    input logic                                             reset,

    input graph_pkg::event_type                             in_event,
    input graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] in_edges,
    input logic  [PRECISION-1 :0]                           in_features [INPUT_DIM-1 : 0],

    input  logic [DATA_WIDTH-1 : 0]                         read,
    output logic [DATA_WIDTH-1 : 0]                         write,
    output logic [ADDR_WIDTH-1 : 0]                         addr,
    output logic                                            ena,
    output logic                                            wea,
    output logic [1:0]                                      mem_ptr
);

    localparam POOL_SIZE = IN_GRAPH_SIZE / OUT_GRAPH_SIZE;
    localparam MEMORY_OPS_NUM = graph_pkg::MEMORY_OPS_NUM;

    localparam logic [1:0] MEM_ADDR_A_X [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_ADDR_A_X;
    localparam bit         MEM_SIGN_A_X [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_SIGN_A_X;

    localparam logic [1:0] MEM_ADDR_B_X [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_ADDR_B_X;
    localparam bit         MEM_SIGN_B_X [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_SIGN_B_X;
    
    localparam logic [1:0] MEM_ADDR_B_Y [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_ADDR_B_Y;
    localparam logic [1:0] MEM_ADDR_A_Y [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_ADDR_A_Y;

    graph_pkg::event_type                             reg_event;
    graph_pkg::event_type                             reg2_event;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] reg_edges;
    logic [1:0]                                       ptr_in;
    logic [1:0]                                       ptr_reg;

    logic [ADDR_WIDTH-1 : 0]                          addr_ena;
    logic [ADDR_WIDTH-1 : 0]                          addr_h1;
    logic [ADDR_WIDTH-1 : 0]                          addr_h2;
    logic [ADDR_WIDTH-1 : 0]                          addr_logic;
    logic [ADDR_WIDTH-1 : 0]                          addr_wea;

    logic [$clog2(MEMORY_OPS_NUM)-1 : 0]              counter;
    logic [$clog2(MEMORY_OPS_NUM)-1 : 0]              counter_reg;
    logic [$clog2(MEMORY_OPS_NUM)-1 : 0]              counter_index;
    logic [$clog2(MEMORY_OPS_NUM)-1 : 0]              counter_index_reg;

    logic [PRECISION-1 :0]                            reg_features [INPUT_DIM-1 : 0];
    logic [PRECISION-1 :0]                            h1_features [INPUT_DIM-1 : 0];
    logic [PRECISION-1 :0]                            h2_features [INPUT_DIM-1 : 0];
    logic [PRECISION-1 :0]                            ena_features [INPUT_DIM-1 : 0];
    logic [PRECISION-1 :0]                            logic_features [INPUT_DIM-1 : 0];    
    
    logic edge_converted;
    logic edge_converted_h1;
    logic edge_converted_h2;
    logic edge_converted_logic;
    logic edge_converted_wea;

    // Counters control, input data assignments
    always @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            counter_reg <= 0;
            reg_event <= '0;
            reg2_event <= '0;
            reg_edges <= '0;
            addr_ena <= '0;
            ptr_in <= '0;
            edge_converted <= '0;
        end
        else begin
            counter_reg  <= counter;
            counter_index  <= counter_reg;
            counter_index_reg  <= counter_index;
            if (in_event.valid) begin
                if ((in_event.t / POOL_SIZE) != (reg_event.t / POOL_SIZE)) begin
                    ptr_in <= (ptr_in == 2) ? 0 : ptr_in+1;
                end
                counter <= 0;
                reg_event <= in_event;
                reg_edges <= in_edges;
                reg_features <= in_features;
            end
            if (counter < MEMORY_OPS_NUM-1) begin
                counter <= counter +1;
            end
            if (edge_converted) begin
                edge_converted <= 1'b0;
            end
            if (counter == MEMORY_OPS_NUM-1 && !edge_converted) begin
                edge_converted <= 1'b1;
            end
            edge_converted_h1 <= edge_converted;
            edge_converted_h2 <= edge_converted_h1;
            edge_converted_logic <= edge_converted_h2;
            edge_converted_wea <= edge_converted_logic;
            reg2_event <= reg_event;
            h1_features <= reg_features;
            h2_features <= h1_features;
            ena_features <= h2_features;
            logic_features <= ena_features;
            addr_h1 <= ((reg2_event.y / POOL_SIZE)*OUT_GRAPH_SIZE) + (reg2_event.x / POOL_SIZE);
            addr_h2 <= addr_h1;
            addr_ena <= addr_h2;
            addr_logic <= addr_ena;
            addr_wea <= addr_logic;
        end
    end

    // Transform IN_GRAPH edges into OUT_GRAPH edges on `conunter`
    logic [$clog2(IN_GRAPH_SIZE) -1 : 0] edge_x_a;
    logic [$clog2(IN_GRAPH_SIZE) -1 : 0] edge_x_b;
    logic [$clog2(IN_GRAPH_SIZE) -1 : 0] edge_y_a;
    logic [$clog2(IN_GRAPH_SIZE) -1 : 0] edge_y_b;
    logic [$clog2(IN_GRAPH_SIZE) -1 : 0] edge_t_a;
    logic [$clog2(IN_GRAPH_SIZE) -1 : 0] edge_t_b;
    logic                                edge_a_val;
    logic                                edge_b_val;

    // In sync with counter
    assign edge_x_a = MEM_SIGN_A_X[counter] ? reg_event.x -  MEM_ADDR_A_X[counter] : reg_event.x +  MEM_ADDR_A_X[counter];
    assign edge_x_b = MEM_SIGN_B_X[counter] ? reg_event.x -  MEM_ADDR_B_X[counter] : reg_event.x +  MEM_ADDR_B_X[counter];
    assign edge_y_a = reg_event.y - MEM_ADDR_A_Y[counter];
    assign edge_y_b = reg_event.y + MEM_ADDR_B_Y[counter];
    assign edge_t_a = reg_event.t - reg_edges[counter].t;
    assign edge_t_b = reg_event.t - reg_edges[MEMORY_OPS_NUM-1+counter].t;
    assign edge_a_val = reg_edges[counter].is_connected && counter != MEMORY_OPS_NUM-1;
    assign edge_b_val = reg_edges[MEMORY_OPS_NUM-1+counter].is_connected;

    // In sync with counter_reg
    logic [$clog2(OUT_GRAPH_SIZE) -1 : 0] edge_x_a_pool;
    logic [$clog2(OUT_GRAPH_SIZE) -1 : 0] edge_x_b_pool;
    logic [$clog2(OUT_GRAPH_SIZE) -1 : 0] edge_y_a_pool;
    logic [$clog2(OUT_GRAPH_SIZE) -1 : 0] edge_y_b_pool;
    logic [$clog2(OUT_GRAPH_SIZE) -1 : 0] edge_t_a_pool;
    logic [$clog2(OUT_GRAPH_SIZE) -1 : 0] edge_t_b_pool;
    logic                                 edge_a_val_reg;
    logic                                 edge_b_val_reg;

    always @(posedge clk) begin
        edge_x_a_pool <= edge_x_a / POOL_SIZE;
        edge_x_b_pool <= edge_x_b / POOL_SIZE;
        edge_y_a_pool <= edge_y_a / POOL_SIZE;
        edge_y_b_pool <= edge_y_b / POOL_SIZE;
        edge_t_a_pool <= edge_t_a / POOL_SIZE;
        edge_t_b_pool <= edge_t_b / POOL_SIZE;
        edge_a_val_reg <= edge_a_val;
        edge_b_val_reg <= edge_b_val;
    end

    logic signed [1:0] diff_x_a;
    logic signed [1:0] diff_x_b;
    logic signed [1:0] diff_y_a;
    logic signed [1:0] diff_y_b;
    logic              diff_t_a;
    logic              diff_t_b;

    assign diff_x_a = edge_x_a_pool - (reg2_event.x / POOL_SIZE);
    assign diff_x_b = edge_x_b_pool - (reg2_event.x / POOL_SIZE);
    assign diff_y_a = edge_y_a_pool - (reg2_event.y / POOL_SIZE);
    assign diff_y_b = edge_y_b_pool - (reg2_event.y / POOL_SIZE);
    assign diff_t_a = (edge_t_a_pool == (reg2_event.t / POOL_SIZE)) ? 0 : 1;
    assign diff_t_b = (edge_t_b_pool == (reg2_event.t / POOL_SIZE)) ? 0 : 1;

    // In sync with counter_index
    logic [5:0] index_a;
    logic [5:0] index_b;
    logic [5:0] index_a_reg;
    logic [5:0] index_b_reg;
    logic       edge_a_val_index;
    logic       edge_b_val_index;

    always @(posedge clk) begin
        // edge address = t*9 + y*3 + x
        index_a <= diff_t_a ? (9+(diff_y_a+1)*3)+(diff_x_a+1) : ((diff_y_a+1)*3)+(diff_x_a+1);
        index_b <= diff_t_b ? (9+(diff_y_b+1)*3)+(diff_x_b+1) : ((diff_y_b+1)*3)+(diff_x_b+1);
        edge_a_val_index <= edge_a_val_reg;
        edge_b_val_index <= edge_b_val_reg;
    end

    logic [17 : 0] out_edges_a = 0;
    logic [17 : 0] out_edges_b = 0;
    logic [17 : 0] out_edges;

    always @(posedge clk) begin
        // We skip the 14th edge on A channel
        if (counter_index == 0) begin
            out_edges_a <= '0;
            out_edges_b <= '0;
        end

        if (counter_index != MEMORY_OPS_NUM-1) begin
            if (edge_a_val_index) begin
                out_edges_a[index_a] <= '1;
            end
        end
        if (edge_b_val_index) begin
            out_edges_b[index_b] <= '1;
        end
        index_a_reg <= index_a;
        index_b_reg <= index_b;

        if (counter_index_reg == 0) begin
            out_edges <= '0;
            if (index_a_reg == index_b_reg) begin
                out_edges[index_a_reg] <= out_edges_a[index_a_reg] | out_edges_b[index_a_reg];
            end
            else begin
                out_edges[index_a_reg] <= out_edges_a[index_a_reg];
                out_edges[index_b_reg] <= out_edges_b[index_b_reg];
            end            
        end
        else if (counter_index_reg == MEMORY_OPS_NUM-1) begin
            out_edges[index_b_reg] <= out_edges_b[index_b_reg] | out_edges[index_b_reg];
        end   
        else begin
            if (index_a_reg == index_b_reg) begin
                out_edges[index_a_reg] <= out_edges_a[index_a_reg] | out_edges_b[index_a_reg] | out_edges[index_a_reg];
            end
            else begin
                out_edges[index_a_reg] <= out_edges_a[index_a_reg] | out_edges[index_a_reg];
                out_edges[index_b_reg] <= out_edges_b[index_b_reg] | out_edges[index_b_reg];
            end   
        end
        out_edges[4] <= 1'b1; //is_event for self_loop (inpossible edge)
    end

    always @(posedge clk) begin
        write[17:0] <= read[17:0] | out_edges;
    end

    logic signed [PRECISION-1 :0] mem_features [INPUT_DIM-1 : 0];    
    logic signed [PRECISION-1 :0] out_features [INPUT_DIM-1 : 0];    

    genvar f, e;
    generate
        for (f = 0; f < INPUT_DIM; f++) begin : feature_assign
            assign mem_features[f] = read[((PRECISION*(f+1))-1)+(9*2) : (PRECISION*f)+(9*2)];
        end
    endgenerate

    genvar i;
    generate
        for (i = 0; i < INPUT_DIM; i++) begin : max_features
            always @(posedge clk) begin
                out_features[i] <= mem_features[i] > logic_features[i] ? mem_features[i] : logic_features[i];
            end
        end
    endgenerate

    genvar j,k;
    generate
        for (k = 0; k < INPUT_DIM; k++) begin : assign_features_out
            assign write[((PRECISION*(k+1))-1)+(9*2) : (PRECISION*k)+(9*2)] = out_features[k];
        end
    endgenerate

    ///////////////////////////////////////////////////////////////
    //                         DELAY EVENT                       //
    ///////////////////////////////////////////////////////////////

    // Output control, valid delay
    logic valid_d1;
    logic valid_d2;

    delay_module #(
        .N        ( 1  ),
        .DELAY    ( 18 )
    ) delay_valid1 (
        .clk   ( clk            ),
        .idata ( in_event.valid ),
        .odata ( valid_d1       )
    );

    delay_module #(
        .N        ( 1 ),
        .DELAY    ( 2 )
    ) delay_valid2 (
        .clk   ( clk      ),
        .idata ( valid_d1 ),
        .odata ( valid_d2 )
    );

    assign ena = (valid_d1 && edge_converted_h2) | wea;
    assign wea = edge_converted_wea && valid_d2;
    assign addr = wea ? addr_wea : addr_ena;

    delay_module #(
        .N      ( 2 ),
        .DELAY  ( 5 )
    ) delay_ptr (
        .clk   ( clk     ),
        .idata ( ptr_in  ),
        .odata ( ptr_reg )
    );

    assign mem_ptr = ptr_reg;

endmodule