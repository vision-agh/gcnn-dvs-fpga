module sync_maxpool #(
    parameter int IN_GRAPH_SIZE  = 32,
    parameter int OUT_GRAPH_SIZE = 16,
    parameter int PRECISION      = graph_pkg::PRECISION,
    parameter int INPUT_DIM      = 32,
    parameter int IN_ADDR_WIDTH  = $clog2(IN_GRAPH_SIZE*IN_GRAPH_SIZE),
    parameter int OUT_ADDR_WIDTH = $clog2(OUT_GRAPH_SIZE*OUT_GRAPH_SIZE),
    parameter int DATA_WIDTH     = (INPUT_DIM*PRECISION) + (9*2) //edges
)(
    input logic                         clk,
    input logic                         reset,

    input logic  [IN_ADDR_WIDTH-1 : 0]  in_addr,
    input logic [17:0]                  in_edges,
    input logic [PRECISION-1 :0]        in_features [INPUT_DIM-1 : 0],
    input logic                         in_valid,
    input logic [1:0]                   in_mem_ptr,

    input  logic [DATA_WIDTH-1 : 0]     read,
    output logic [DATA_WIDTH-1 : 0]     write,
    output logic [OUT_ADDR_WIDTH-1 : 0] addr,
    output logic                        ena,
    output logic                        wea,
    output logic [1:0]                  mem_ptr
);

    localparam POOL_SIZE = IN_GRAPH_SIZE / OUT_GRAPH_SIZE;

    localparam MEMORY_OPS_NUM = 9;

    localparam logic MEM_ADDR_X [8:0] = {1, 0, 1, 1, 0, 1, 1, 0, 1};
    localparam logic MEM_SIGN_X [8:0] = {0, 0, 1, 0, 0, 1, 0, 0, 1};
    localparam logic MEM_ADDR_Y [8:0] = {1, 1, 1, 0, 0, 0, 1, 1, 1};
    localparam logic MEM_SIGN_Y [8:0] = {0, 0, 0, 0, 0, 0, 1, 1, 1};

    graph_pkg::event_type              reg_event;
    graph_pkg::event_type              reg2_event;
    logic [17:0]                       reg_edges;
    logic [1:0]                        ptr_in_reg;
    logic [1:0]                        ptr_reg;

    logic [OUT_ADDR_WIDTH-1 : 0]       addr_ena;
    logic [OUT_ADDR_WIDTH-1 : 0]       addr_h1;
    logic [OUT_ADDR_WIDTH-1 : 0]       addr_h2;
    logic [OUT_ADDR_WIDTH-1 : 0]       addr_logic;
    logic [OUT_ADDR_WIDTH-1 : 0]       addr_wea;

    logic [$clog2(MEMORY_OPS_NUM) : 0] counter;
    logic [$clog2(MEMORY_OPS_NUM) : 0] counter_reg;
    logic [$clog2(MEMORY_OPS_NUM) : 0] counter_index;
    logic [$clog2(MEMORY_OPS_NUM) : 0] counter_index_reg;
    logic [PRECISION-1 :0]             reg_features [INPUT_DIM-1 : 0];
    logic [PRECISION-1 :0]             h1_features [INPUT_DIM-1 : 0];
    logic [PRECISION-1 :0]             h2_features [INPUT_DIM-1 : 0];
    logic [PRECISION-1 :0]             ena_features [INPUT_DIM-1 : 0];
    logic [PRECISION-1 :0]             logic_features [INPUT_DIM-1 : 0];
    
    logic edge_converted;
    logic edge_converted_h1;
    logic edge_converted_h2;
    logic edge_converted_logic;
    logic edge_converted_wea;
    logic is_start;
    logic [3 :0] t_diff;   //Only for POLL2x2

    // Counters control, input data assignments
    always @(posedge clk) begin
        if (reset) begin
            counter <= MEMORY_OPS_NUM-1;
            counter_reg <= 0;
            reg_event <= '0;
            reg2_event <= '0;
            reg_edges <= '0;
            addr_ena <= '0;
            edge_converted <= 1;
            t_diff <= 0;
            ptr_reg <= 0;
            is_start <= 0;
        end
        else begin
            counter_reg  <= counter;
            counter_index  <= counter_reg;
            counter_index_reg  <= counter_index;
            if (in_mem_ptr != ptr_in_reg) begin
                t_diff <= t_diff == POOL_SIZE-1 ? '0 : t_diff+1;
                if (t_diff == POOL_SIZE-1) begin
                    ptr_reg <= (ptr_reg == 2) ? 0 : ptr_reg+1;
                end
            end
            ptr_in_reg <= in_mem_ptr;
            if (in_valid && in_edges[4]) begin
                is_start <= 1'b1;
                counter <= 0;
                reg_event.x <= in_addr % IN_GRAPH_SIZE;
                reg_event.y <= (in_addr - (in_addr % IN_GRAPH_SIZE))/IN_GRAPH_SIZE;
                reg_edges <= in_edges;
                reg_features <= in_features;
            end
            if (counter < MEMORY_OPS_NUM-1) begin
                counter <= counter +1;
            end
            if (edge_converted) begin
                edge_converted <= 1'b0;
            end
            if (counter == MEMORY_OPS_NUM-1 && !edge_converted && is_start) begin
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
    logic [$clog2(IN_GRAPH_SIZE) -1 : 0] edge_x;
    logic [$clog2(IN_GRAPH_SIZE) -1 : 0] edge_y;
    logic                                edge_a_val;
    logic                                edge_b_val;

    // In sync with counter
    assign edge_x = MEM_SIGN_X[counter] ? reg_event.x - 1 : reg_event.x +  MEM_ADDR_X[counter];
    assign edge_y = MEM_SIGN_Y[counter] ? reg_event.y - 1 : reg_event.y +  MEM_ADDR_Y[counter];
    assign edge_a_val = reg_edges[counter] && counter != 4;
    assign edge_b_val = reg_edges[9+counter];

    // In sync with counter_reg
    logic [$clog2(OUT_GRAPH_SIZE) -1 : 0] edge_x_pool;
    logic [$clog2(OUT_GRAPH_SIZE) -1 : 0] edge_y_pool;
    logic                                 edge_a_val_reg;
    logic                                 edge_b_val_reg;

    always @(posedge clk) begin
        edge_x_pool <= edge_x / POOL_SIZE;
        edge_y_pool <= edge_y / POOL_SIZE;
        edge_a_val_reg <= edge_a_val;
        edge_b_val_reg <= edge_b_val;
    end

    logic signed [1:0] diff_x;
    logic signed [1:0] diff_y;

    assign diff_x = edge_x_pool - (reg2_event.x / POOL_SIZE);
    assign diff_y = edge_y_pool - (reg2_event.y / POOL_SIZE);

    // In sync with counter_index
    logic [5:0] index_a;
    logic [5:0] index_b;
    logic [5:0] index_a_reg;
    logic [5:0] index_b_reg;
    logic       edge_a_val_index;
    logic       edge_b_val_index;

    always @(posedge clk) begin
        index_a <= ((diff_y+1)*3)+(diff_x+1);
        index_b <= (t_diff == 0) ? (9+(diff_y+1)*3)+(diff_x+1) : ((diff_y+1)*3)+(diff_x+1);
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

        if (edge_a_val_index) begin
            out_edges_a[index_a] <= '1;
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
//        else if (counter_index_reg == MEMORY_OPS_NUM-1) begin
//            out_edges[index_b_reg] <= out_edges_b[index_b_reg] | out_edges[index_b_reg];
//        end   
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
        .DELAY    ( 12 )
    ) delay_valid1 (
        .clk   ( clk                     ),
        .idata ( in_valid && in_edges[4] ),
        .odata ( valid_d1                )
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
        .clk   ( clk        ),
        .idata ( ptr_reg    ),
        .odata ( mem_ptr    )
    );

endmodule
