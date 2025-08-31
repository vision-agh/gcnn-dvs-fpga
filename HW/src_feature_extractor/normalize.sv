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

    graph_pkg::event_type        register;
    logic [INPUT_BIT_TIME-1: 0]  timestamp_reg;
    logic [COUNTER_WIDTH-1 : 0]  sample_counter = 0;
    logic [INPUT_BIT_TIME-1 : 0] time_window_num = TIME_WINDOW;

    always @(posedge clk) begin
        if (reset) begin
            register <= '0;
            sample_counter <= 1'b0;
            time_window_num <= TIME_WINDOW;
        end
        else begin
            timestamp_reg <= ((timestamp % TIME_WINDOW)*(GRAPH_SIZE));
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
            out_event <= register;
            out_event.t <= timestamp_reg / TIME_WINDOW;
            window_counter <= sample_counter;
        end
    end


endmodule : normalize
