module top_synth #(
    parameter int MAX_X_COORD    = 240,
    parameter int MAX_Y_COORD    = 180,
    parameter int INPUT_BIT_TIME = 32,   
    parameter int INPUT_BIT_X    = 8,
    parameter int INPUT_BIT_Y    = 8

)( 
    input logic                       clk,
    input logic                       reset,
    input logic [INPUT_BIT_TIME-1: 0] timestamp,
    input logic [INPUT_BIT_X-1 : 0]   x_coord,
    input logic [INPUT_BIT_Y-1 : 0]   y_coord,
    input logic                       polarity,
    input logic                       is_valid,

    output logic [$clog2(4*4*4)-1 : 0]        out_addr,
    output logic [graph_pkg::PRECISION-1 : 0] out_data,
    output logic                              out_valid
);

    top #(
        .MAX_X_COORD ( MAX_X_COORD ),
        .MAX_Y_COORD ( MAX_Y_COORD )
    ) u_top (
        .clk        ( clk         ),
        .reset      ( reset       ),
        .timestamp  ( timestamp   ),
        .x_coord    ( x_coord     ),
        .y_coord    ( y_coord     ),
        .polarity   ( polarity    ),
        .is_valid   ( is_valid    ),
        .out_addr  ( out_addr     ),
        .out_data  ( out_data     ),
        .out_valid ( out_valid    )
    );


endmodule
