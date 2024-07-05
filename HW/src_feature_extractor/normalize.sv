`timescale 1ns / 1ps

module normalize #(
    parameter int MAX_X_COORD    = 240,
    parameter int MAX_Y_COORD    = 180,
    parameter int GRAPH_SIZE     = 128,
    parameter int INPUT_BIT_TIME = 32,
    parameter int INPUT_BIT_X    = 8,
    parameter int INPUT_BIT_Y    = 8,
    parameter int TIME_WINDOW    = 50000
)( 
    input logic                       clk,
    input logic                       reset,
    input logic [INPUT_BIT_TIME-1: 0] timestamp,
    input logic [INPUT_BIT_X-1 : 0]   x_coord,
    input logic [INPUT_BIT_Y-1 : 0]   y_coord,
    input logic                       polarity,
    input logic                       is_valid,
    output graph_pkg::event_type      out_event,
    output logic                      reset_context
);

    graph_pkg::event_type       register;
    logic [INPUT_BIT_TIME-1: 0] timestamp_reg;
    logic                       reset_mem;
    logic                       reset_mem_reg;

    always @(posedge clk) begin
        if (reset) begin
            register <= '0;
            reset_mem <= 1'b0;
        end
        else begin
            timestamp_reg <= ((timestamp % TIME_WINDOW)*(GRAPH_SIZE));
            register.x <= (x_coord*(GRAPH_SIZE)/MAX_X_COORD);
            register.y <= (y_coord*(GRAPH_SIZE)/MAX_Y_COORD);
            register.p <= polarity;
            reset_mem <= 1'b0;
            register.valid <= '0;
            if (is_valid) begin
                register.valid <= '1;
                if (timestamp > TIME_WINDOW) begin
                    reset_mem <= 1'b1;
                end
            end
            out_event <= register;
            out_event.t <= timestamp_reg / TIME_WINDOW;
            reset_mem_reg <= reset_mem;
        end
    end

    assign reset_context = reset_mem;

endmodule : normalize
