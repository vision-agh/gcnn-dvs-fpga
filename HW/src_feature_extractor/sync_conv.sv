`timescale 1ns / 1ps

module sync_conv #(
    parameter int GRAPH_SIZE     = 32,
    parameter int PRECISION      = graph_pkg::PRECISION,
    parameter int INPUT_DIM      = 16,
    parameter int OUTPUT_DIM     = 32,
    parameter int ADDR_WIDTH     = $clog2(GRAPH_SIZE*GRAPH_SIZE),
    parameter int IN_DATA_WIDTH  = (INPUT_DIM*PRECISION) + (9*2), //edges
    parameter int OUT_DATA_WIDTH = (OUTPUT_DIM*PRECISION) + (9*2), //edges
    parameter int ZERO_POINT_IN = 126,
    parameter int ZERO_POINT_OUT = 120,
    parameter int MULTIPLIER_OUT = 21665426,
    parameter int ZERO_POINT_WEIGHT = 0,
    parameter string INIT_PATH      = "???",
    parameter int SCALE_IN       = 31

)( 
    input logic                     clk,
    input logic                     reset,

    input logic  [IN_DATA_WIDTH-1 : 0] in_data_a,
    input logic  [IN_DATA_WIDTH-1 : 0] in_data_b,
    output logic [ADDR_WIDTH-1 : 0]    in_addr,

    output logic                       in_clean,
    input  logic                       in_switch,

    output logic [ADDR_WIDTH-1 : 0]   out_addr,
    output logic [17:0]               out_edges,
    output logic [PRECISION-1 :0]     features [OUTPUT_DIM-1 : 0],
    output logic                      out_valid,
    output logic [1:0]                mem_ptr
);

    localparam CONV_IN_DIM = INPUT_DIM+3;
    localparam ITER_CNT_WIDTH = $clog2(OUTPUT_DIM);
    localparam IDLE = 2'd0;
    localparam CONV = 2'd1;
    localparam ZERO = 2'd2;
    logic [1:0] state = IDLE;
    logic [1:0] state_h1 = IDLE;
    logic [1:0] state_read = IDLE;
    logic [1:0] ptr_in;

    localparam logic MEM_ADDR_X [8:0] = {1,  1,  0, 1, 1, 0, 1, 1, 0};
    localparam logic signed [PRECISION:0] FEATURES_X [8:0] = {-SCALE_IN, SCALE_IN, 0, -SCALE_IN, SCALE_IN,  0, -SCALE_IN, SCALE_IN, -0};
    localparam logic MEM_SIGN_X [8:0] = {1,  0,  0, 1, 0, 0, 1, 0, 0};

    localparam logic MEM_ADDR_Y [8:0] = {1, 1, 1, 1, 1, 1, 0, 0, 0};
    localparam logic signed [PRECISION:0] FEATURES_Y [8:0] = {-SCALE_IN, -SCALE_IN, -SCALE_IN, SCALE_IN, SCALE_IN,  SCALE_IN, 0, 0, 0};
    localparam logic MEM_SIGN_Y [8:0] = {1, 1, 1, 0, 0, 0, 0, 0, 0};

    logic [ADDR_WIDTH-1 : 0] zero_counter; //Count to (GRAPH_SIZE*GRAPH_SIZE)
    logic [ADDR_WIDTH-1 : 0] conv_counter; //Count to (GRAPH_SIZE*GRAPH_SIZE)
    logic [ADDR_WIDTH-1 : 0] conv_counter_h1;   //Count to (GRAPH_SIZE*GRAPH_SIZE)
    logic [ADDR_WIDTH-1 : 0] conv_counter_read; //Count to (GRAPH_SIZE*GRAPH_SIZE)
    logic [3 : 0]            edge_counter; //Count to 9
    logic [3 : 0]            edge_counter_h1; //Count to 9
    logic [3 : 0]            edge_counter_read; //Count to 9
    logic [3 : 0]            edge_counter_mul_in; //Count to 9
    logic [3 : 0]            edge_counter_mul_h1; //Count to 9
    logic [3 : 0]            edge_counter_mul_h2; //Count to 9
    logic [3 : 0]            edge_counter_mul_out; //Count to 9
    logic [3 : 0]            edge_counter_compare; //Count to 9
    logic [3 : 0]            edge_counter_accumulate; //Count to 9
    
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter; //Count to OUTPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_h1; //Count to OUTPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_read; //Count to OUTPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_mul_in; //Count to OUTPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_mul_h1; //Count to OUTPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_mul_h2; //Count to OUTPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_mul_out; //Count to OUTPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_compare; //Count to OUTPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_accumulate; //Count to OUTPUT_DIM

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            zero_counter <= '0;
            conv_counter <= '0;
            edge_counter <= '0;
            iter_counter <= '0;
            ptr_in <= '0;
        end
        else begin
            // Perform Convolution after in_switch
            if (state == CONV) begin
                if (iter_counter == OUTPUT_DIM-1) begin
                    iter_counter <= '0;
                    edge_counter <= edge_counter + 1;
                end
                if (edge_counter == 8 && iter_counter == OUTPUT_DIM-1) begin
                    edge_counter <= '0;
                    conv_counter <= conv_counter + 1;
                end
                iter_counter <= iter_counter + 1;
            end
            if (in_switch) begin
                state <= CONV;
                conv_counter <= '0;
                iter_counter <= '0;
                edge_counter <= '0;
            end
            // Reset oldest memory channel after
            if (conv_counter == (GRAPH_SIZE*GRAPH_SIZE)-1 && edge_counter == 8 && iter_counter == OUTPUT_DIM-1) begin
                state <= ZERO;
                ptr_in <= (ptr_in == 2) ? 0 : ptr_in+1;
                zero_counter <= '0;
            end
            // Wait for next channel after reseting
            if (state == ZERO && zero_counter == ((GRAPH_SIZE*GRAPH_SIZE)-1)) begin
                state <= IDLE;
            end
            else begin
                if (state == ZERO) zero_counter <= zero_counter+1;
            end
            state_read <= state_h1;
            state_h1 <= state;
            conv_counter_h1 <= conv_counter;
            conv_counter_read <= conv_counter_h1;

            iter_counter_h1 <= iter_counter;
            iter_counter_read <= iter_counter_h1;
            iter_counter_mul_in <= iter_counter_read;
            iter_counter_mul_h1 <= iter_counter_mul_in;
            iter_counter_mul_h2 <= iter_counter_mul_h1;
            iter_counter_mul_out <= iter_counter_mul_h2;
            iter_counter_compare <= iter_counter_mul_out;
            iter_counter_accumulate <= iter_counter_compare;

            edge_counter_h1 <= edge_counter;
            edge_counter_read <= edge_counter_h1;
            edge_counter_mul_in <= edge_counter_read;
            edge_counter_mul_h1 <= edge_counter_mul_in;
            edge_counter_mul_h2 <= edge_counter_mul_h1;
            edge_counter_mul_out <= edge_counter_mul_h2;
            edge_counter_compare <= edge_counter_mul_out;
            edge_counter_accumulate <= edge_counter_compare;
        end
    end

    logic [$clog2(GRAPH_SIZE) -1 :0] node_x;
    logic [$clog2(GRAPH_SIZE) -1 :0] node_y;
    logic [$clog2(GRAPH_SIZE) -1 :0] addr_x;
    logic [$clog2(GRAPH_SIZE) -1 :0] addr_y;
    logic condition_x;
    logic condition_y;

    // Y* GRAPH + X
    assign node_x = (conv_counter % GRAPH_SIZE);
    assign node_y = (conv_counter - (conv_counter % GRAPH_SIZE)) / GRAPH_SIZE;

    always @(posedge clk) begin
        addr_x <= MEM_SIGN_X[edge_counter] ? node_x - 1 : node_x + MEM_ADDR_X[edge_counter];
        addr_y <= MEM_SIGN_Y[edge_counter] ? node_y - 1 : node_y + MEM_ADDR_Y[edge_counter];
        condition_x <= MEM_SIGN_X[edge_counter] ? (node_x > 1)
                                               : ((node_x + MEM_ADDR_X[edge_counter]) < GRAPH_SIZE);
        condition_y <= MEM_SIGN_Y[edge_counter] ? (node_y > 1)
                                               : ((node_y + MEM_ADDR_X[edge_counter]) < GRAPH_SIZE);

    end
    assign in_addr = (state == CONV) ? ((addr_y * GRAPH_SIZE) + addr_x) : zero_counter;
    assign in_clean = (state == ZERO);

    logic [17:0] edges;
    logic signed [PRECISION:0]   feature_data_a [INPUT_DIM-1:0];
    logic signed [PRECISION:0]   feature_data_b [INPUT_DIM-1:0];
    logic signed [PRECISION:0]   feature_mat_a [CONV_IN_DIM-1:0];
    logic signed [PRECISION:0]   feature_mat_b [CONV_IN_DIM-1:0];
    logic        [PRECISION-1:0] output_mat_a;
    logic        [PRECISION-1:0] output_mat_b;
    logic        [PRECISION-1:0] output_mat_a_full [OUTPUT_DIM-1:0];
    logic        [PRECISION-1:0] output_mat_b_full [OUTPUT_DIM-1:0];
    logic        [PRECISION-1:0] output_mat_full   [OUTPUT_DIM-1:0];
    logic        [PRECISION-1:0] out_features      [OUTPUT_DIM-1:0];

    logic [5:0] index;
    logic [5:0] index_reg;
    logic signed [1:0] diff_x;
    logic signed [1:0] diff_y;    

    assign diff_x = (MEM_SIGN_X[edge_counter_read]) ? -1 : MEM_ADDR_X[edge_counter_read];
    assign diff_y = (MEM_SIGN_Y[edge_counter_read]) ? -1 : MEM_ADDR_Y[edge_counter_read];

    // PORT A -  Self-loop on 1st iteration
    genvar a;
    generate
        for (a = 0; a < INPUT_DIM; a++) begin : port_a_assign
            always @(posedge clk) begin
                feature_data_a[a][PRECISION-1 : 0] = {in_data_a[((PRECISION)*(a+1))-1+(9*2) : (PRECISION*a)+(9*2)]};
                feature_data_a[a][PRECISION] = 0;
                feature_mat_a[a] <= feature_data_a[a]-ZERO_POINT_IN;
            end
        end
    endgenerate

    logic signed [PRECISION:0] single_weight_reg [INPUT_DIM+2:0];
    logic signed [31:0]        single_bias_reg;
    logic signed [PRECISION:0] single_weight [INPUT_DIM+2:0];
    logic signed [31:0]        single_bias;

    localparam WEIGHT_WIDTH = ((INPUT_DIM+3)*(PRECISION))+32; //bias
    logic [WEIGHT_WIDTH-1 : 0] weight_mem;

    memory_weights #(
        .AWIDTH   ( ITER_CNT_WIDTH ),
        .DWIDTH   ( WEIGHT_WIDTH   ),
        .RAM_TYPE ( "block"        ),
        .INIT_PATH ( INIT_PATH     )
    ) weights_memory   (
        .clk      ( clk      ),
        .read     ( state == CONV   ),
        .addr     ( iter_counter    ),
        .dout     ( weight_mem      )
    );

    always @(posedge clk) begin
        feature_mat_a[INPUT_DIM]   <= FEATURES_X[edge_counter_read];
        feature_mat_a[INPUT_DIM+1] <= FEATURES_Y[edge_counter_read];
        feature_mat_a[INPUT_DIM+2] <= 0; //current events on A channel
    end

    genvar w;
    generate
        for (w = 0; w < INPUT_DIM+3; w++) begin : weights_assign
            always @(posedge clk) begin
                single_weight_reg[w] <= weight_mem[(((PRECISION)*(w+1))-1)+32 : ((PRECISION)*w)+32] - ZERO_POINT_WEIGHT;
            end
        end
    endgenerate

    always @(posedge clk) begin
        single_bias_reg <= weight_mem[31:0];
        single_weight <= single_weight_reg;
        single_bias <= single_bias_reg;
    end

    vector_multiplication #(
        .INPUT_DIM         ( INPUT_DIM+3    ),
        .MULTIPLIER        ( MULTIPLIER_OUT ),
        .ZERO_POINT        ( ZERO_POINT_OUT )
    ) mul_a (
        .clk             ( clk           ),
        .reset           ( reset         ),
        .feature_matrix  ( feature_mat_a ),
        .weight_matrix   ( single_weight ),
        .bias            ( single_bias   ),
        .output_matrix   ( output_mat_a  )
    );

    // PORT B
    genvar b;
    generate
        for (b = 0; b < INPUT_DIM; b++) begin : port_b_assign
            always @(posedge clk) begin
                feature_data_b[b][PRECISION-1 : 0] = {in_data_b[((PRECISION)*(b+1))-1+(9*2) : (PRECISION*b)+(9*2)]};
                feature_data_b[b][PRECISION] = 0;
                feature_mat_b[b] <= feature_data_b[b]-ZERO_POINT_IN;
            end
        end
    endgenerate

    always @(posedge clk) begin
        feature_mat_b[INPUT_DIM]   <= FEATURES_X[edge_counter_read];
        feature_mat_b[INPUT_DIM+1] <= FEATURES_Y[edge_counter_read];
        feature_mat_b[INPUT_DIM+2] <= -SCALE_IN; //old events on B channel
    end

    vector_multiplication #(
        .INPUT_DIM         ( INPUT_DIM+3    ),
        .MULTIPLIER        ( MULTIPLIER_OUT ),
        .ZERO_POINT        ( ZERO_POINT_OUT )
    ) mul_b (
        .clk             ( clk           ),
        .reset           ( reset         ),
        .feature_matrix  ( feature_mat_b ),
        .weight_matrix   ( single_weight ),
        .bias            ( single_bias   ),
        .output_matrix   ( output_mat_b  )
    );

    logic is_connected_a;
    logic is_connected_b;
    logic is_connected_a_reg;
    logic is_connected_b_reg;
    logic is_connected_a_h1;
    logic is_connected_b_h1;
    logic data_ready;
    logic write_ready;

    always @(posedge clk) begin
        if (state_read == CONV) begin
            if (edge_counter_read == 0) begin
                edges <= in_data_a[17:0];
            end
            index <= ((diff_y+1)*3)+(diff_x+1);
            is_connected_a <= edges[index];
            is_connected_b <= edges[index+9];
            is_connected_a_h1 <= is_connected_a;
            is_connected_b_h1 <= is_connected_b;
            is_connected_a_reg <= is_connected_a_h1;
            is_connected_b_reg <= is_connected_b_h1;
            data_ready <= (edge_counter_accumulate == 8 && iter_counter_accumulate == OUTPUT_DIM-1);
            out_valid <= data_ready;
        end
    end

    // Handle outputs of multiplayers
    always @(posedge clk) begin
        output_mat_a_full[iter_counter_mul_out] <= is_connected_a_reg ? output_mat_a : '0;
        output_mat_b_full[iter_counter_mul_out] <= is_connected_b_reg ? output_mat_b : '0;      
    end

    always @(posedge clk) begin
        output_mat_full[iter_counter_compare] <= output_mat_a_full[iter_counter_compare] > output_mat_b_full[iter_counter_compare] ? output_mat_a_full[iter_counter_compare]
                                                                                                                                   : output_mat_b_full[iter_counter_compare];
        if (iter_counter_accumulate == 0 && edge_counter_accumulate == 0) begin
            out_features <= '{default:ZERO_POINT_OUT};;
            out_features[iter_counter_accumulate] <= ZERO_POINT_OUT >= output_mat_full[iter_counter_accumulate] ? ZERO_POINT_OUT : output_mat_full[iter_counter_accumulate];
        end
        else begin
            out_features[iter_counter_accumulate] <= out_features[iter_counter_accumulate] > output_mat_full[iter_counter_accumulate] ? out_features[iter_counter_accumulate] : output_mat_full[iter_counter_accumulate];
        end
        features <= out_features;
    end

    delay_module #(
        .N        ( 18 ),
        .DELAY    ( 10  )
    ) delay_edge (
        .clk   ( clk       ),
        .idata ( edges     ),
        .odata ( out_edges )
    );

    delay_module #(
        .N        ( ADDR_WIDTH ),
        .DELAY    ( 10  )
    ) delay_addr (
        .clk   ( clk      ),
        .idata ( ((node_y * GRAPH_SIZE) + node_x) ),
        .odata ( out_addr                         )
    );

    delay_module #(
        .N        ( 2 ),
        .DELAY    ( 10  )
    ) delay_ptr (
        .clk   ( clk     ),
        .idata ( ptr_in  ),
        .odata ( mem_ptr )
    );

    // synthesis translate_off
    always @(posedge clk) begin
        if (state != IDLE && in_switch) begin
            $display("CONVOLUTION THROUGHPUT IS TOO SMALL - EXIT THE SIMULATION");
            $stop;
        end
    end
    // synthesis translate_on

endmodule