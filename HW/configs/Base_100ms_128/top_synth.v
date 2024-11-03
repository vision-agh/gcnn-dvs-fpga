module top_mod_synth #(
    // Sensor resolution [for this demo - 128x128]
    parameter MAX_X_COORD    = 128,
    parameter MAX_Y_COORD    = 128,

    // Timestamp and coordinate values precision
    parameter INPUT_BIT_TIME = 32,
    parameter INPUT_BIT_X    = 8,
    parameter INPUT_BIT_Y    = 8
)( 
    input                         clk,          // System clock (200MHz)
    input                         reset,        // System reset
    input  [INPUT_BIT_TIME-1: 0]  timestamp,    // Input events timestamp
    input  [INPUT_BIT_X-1 : 0]    x_coord,      // Input events x coordinate
    input  [INPUT_BIT_Y-1 : 0]    y_coord,      // Input events x coordinate
    input                         polarity,     // Input events polarity
    input                         is_valid,     // The is_valid flag for input events

    output [5 : 0]  out_addr,     // Output feature map element address
    output [7 : 0]                out_data,          // Output feature map element data
    output                        out_valid     // The is_valid flag for output feature map
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
        .out_addr   ( out_addr    ),
        .out_data   ( out_data    ),
        .out_valid  ( out_valid   )
    );

endmodule
