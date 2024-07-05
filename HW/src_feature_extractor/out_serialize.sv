`timescale 1ns / 1ps

module out_serialize #(
    parameter int GRAPH_SIZE     = 4,
    parameter int PRECISION      = graph_pkg::PRECISION,
    parameter int INPUT_DIM      = 64,
    parameter int ADDR_WIDTH     = $clog2(GRAPH_SIZE*GRAPH_SIZE*GRAPH_SIZE),
    parameter int IN_DATA_WIDTH  = (INPUT_DIM*PRECISION) + (9*2),
    parameter int ZERO_POINT     = 1

)( 
    input logic                        clk,
    input logic                        reset,

    input logic  [IN_DATA_WIDTH-1 : 0] in_data,
    output logic [ADDR_WIDTH-1 : 0]    in_addr,

    output logic                       in_clean,
    input  logic                       in_switch,

    output logic [ADDR_WIDTH-1 : 0]    out_addr,
    output logic [PRECISION-1 : 0]     out_data,
    output logic                       out_valid
);

    localparam ITER_CNT_WIDTH = $clog2(INPUT_DIM);
    localparam IDLE = 2'd0;
    localparam CONV = 2'd1;
    localparam ZERO = 2'd2;
    logic [1:0] state = IDLE;
    logic [1:0] state_h1 = IDLE;
    logic [1:0] state_read = IDLE;

    logic [ADDR_WIDTH-1 : 0] zero_counter; //Count to (GRAPH_SIZE*GRAPH_SIZE)
    logic [ADDR_WIDTH-1 : 0] conv_counter; //Count to (GRAPH_SIZE*GRAPH_SIZE)
    logic [ADDR_WIDTH-1 : 0] conv_counter_h1;   //Count to (GRAPH_SIZE*GRAPH_SIZE)
    logic [ADDR_WIDTH-1 : 0] conv_counter_read; //Count to (GRAPH_SIZE*GRAPH_SIZE)
    
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter; //Count to INPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_h1; //Count to INPUT_DIM
    logic [ITER_CNT_WIDTH-1 : 0] iter_counter_out; //Count to INPUT_DIM
    logic [$clog2(GRAPH_SIZE)-1 :0] node_t;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            zero_counter <= '0;
            conv_counter <= '0;
            iter_counter <= '0;
            node_t <= GRAPH_SIZE-1;
        end
        else begin
                // Perform Convolution after in_switch
            if (state == CONV) begin
                if (iter_counter == INPUT_DIM-1) begin
                    iter_counter <= '0;
                end
                if (iter_counter == INPUT_DIM-1) begin
                    conv_counter <= conv_counter + 1;
                end
                iter_counter <= iter_counter + 1;
            end
            if (in_switch) begin
                node_t <= node_t + 1;
                state <= CONV;
                conv_counter <= '0;
                iter_counter <= '0;
            end
            // Reset oldest memory channel after
            if (conv_counter == (GRAPH_SIZE*GRAPH_SIZE)-1 && iter_counter == INPUT_DIM-1) begin
                state <= ZERO;
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

            iter_counter_h1 <= iter_counter;
            iter_counter_out <= iter_counter_h1;
        end
    end

    logic [$clog2(GRAPH_SIZE) -1 :0] node_x;
    logic [$clog2(GRAPH_SIZE) -1 :0] node_y;
    logic condition_x;
    logic reg_valid;
    logic condition_y;

    assign in_addr = (state == CONV) ? conv_counter : zero_counter;
    assign in_clean = (state == ZERO);

    logic [PRECISION-1:0]   feature_data [INPUT_DIM-1:0];

    genvar a;
    generate
        for (a = 0; a < INPUT_DIM; a++) begin : data_assign
            always @(posedge clk) begin
                feature_data[a] <= {in_data[((PRECISION)*(a+1))-1+(9*2) : (PRECISION*a)+(9*2)]} > ZERO_POINT ? {in_data[((PRECISION)*(a+1))-1+(9*2) : (PRECISION*a)+(9*2)]} : ZERO_POINT;
            end
        end
    endgenerate

    always @(posedge clk) begin
        // Y* GRAPH + X
        node_x <= (conv_counter_h1 % GRAPH_SIZE);
        node_y <= (conv_counter_h1 - (conv_counter_h1 % GRAPH_SIZE)) / GRAPH_SIZE;

        out_data <= feature_data[iter_counter_out];
        out_addr <= (16 * node_x) + (4 * node_y) + node_t;
        reg_valid <= (state == CONV) && !(iter_counter == 0 && conv_counter==0);
        out_valid <= reg_valid;
    end

endmodule
