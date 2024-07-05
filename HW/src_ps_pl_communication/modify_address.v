`timescale 1ns / 1ps

module modify_address #(
    parameter INPUT_SIZE = 13,
    parameter OUTPUT_SIZE = 10,
    parameter BYTES_PER_DATA = 4
)(
    input [INPUT_SIZE-1:0]   signal_in,
    output [OUTPUT_SIZE-1:0] signal_out
);

    assign signal_out = signal_in / BYTES_PER_DATA;

endmodule
