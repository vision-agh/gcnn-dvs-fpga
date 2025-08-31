`timescale 1ns / 1ps

module normalize #(
    parameter int MAX_X_COORD    = 128,
    parameter int MAX_Y_COORD    = 128,
    parameter int GRAPH_SIZE     = 128,
    parameter int INPUT_BIT_TIME = 32,
    parameter int INPUT_BIT_X    = 7,
    parameter int INPUT_BIT_Y    = 7,
    parameter int COUNTER_WIDTH  = 9,
    parameter int TIME_WINDOW    = 50000
)( 
    input logic                        clk,
    input logic                        reset,
    input logic [INPUT_BIT_TIME-1: 0]  timestamp,
    input logic [INPUT_BIT_X-1 : 0]    x_coord,
    input logic [INPUT_BIT_Y-1 : 0]    y_coord,
    input logic                        polarity,
    input logic                        is_valid,
    output graph_pkg::event_type       out_event,
    output logic [COUNTER_WIDTH-1 : 0] window_counter
);

    localparam int THRESHOLD = 3125;

    graph_pkg::event_type        register;
    graph_pkg::event_type        register2;
    graph_pkg::event_type        register3;
    logic [INPUT_BIT_TIME-1: 0]  timestamp_reg;
    logic [INPUT_BIT_TIME-1: 0]  timestamp_reg2;
    logic [INPUT_BIT_TIME-1: 0]  timestamp_reg3;
    logic [INPUT_BIT_TIME-1: 0]  timestamp_cntr = 0;
    logic [10 : 0]               clk_cntr = 0;
    logic [31: 0]                iter = 1;
    logic [COUNTER_WIDTH-1 : 0]  sample_counter = 0;
    logic [COUNTER_WIDTH-1 : 0]  sample_counter2 = 0;
    logic [COUNTER_WIDTH-1 : 0]  sample_counter3 = 0;
    logic [INPUT_BIT_TIME-1 : 0] time_window_num = TIME_WINDOW;
    logic is_first = 1;

    always @(posedge clk) begin
        if (reset) begin
            register <= '0;
            sample_counter <= 1'b0;
            time_window_num <= TIME_WINDOW;
            is_first <= 1;
        end
        else begin
            if (is_first && is_valid) begin
                timestamp_cntr <= timestamp;
                clk_cntr <= '0;
                is_first <= 0;
            end
            if (!is_first) begin
                clk_cntr <= clk_cntr+5;
                if (clk_cntr >= 1000) begin
                    timestamp_cntr <= timestamp_cntr+1;
                    clk_cntr <= '0;
                end
                if (is_valid) begin
                    timestamp_cntr <= timestamp;
                    clk_cntr <= '0;
                end
            end
            timestamp_reg <= timestamp;
            register.x <= x_coord;
            register.y <= y_coord;
            register.p <= polarity;
            register.valid <= '0;
            if (is_valid) begin
                register.valid <= '1;
                if (timestamp > time_window_num) begin
                    sample_counter <= sample_counter + 1;
                    time_window_num <= time_window_num + TIME_WINDOW;
                end
            end
            if (timestamp_cntr >= (THRESHOLD*iter) && !is_valid) begin
                register.x <= '0;
                register.y <= '0;
                register.p <= '0;
                register.valid <= '1;
                iter = iter+1;
                timestamp_reg <= timestamp_cntr;
            end
            timestamp_reg2 <= timestamp_reg % TIME_WINDOW;
            timestamp_reg3 <= timestamp_reg2 * GRAPH_SIZE;
            register2 <= register;
            register3 <= register2;
            out_event <= register3;
            out_event.t <= timestamp_reg3 / TIME_WINDOW;
            sample_counter2 <= sample_counter;
            sample_counter3 <= sample_counter2;
            window_counter <= sample_counter3;
        end
    end


endmodule : normalize