`timescale 1ns / 1ps

module generate_graph #(
    parameter int MAX_X_COORD    = 128,
    parameter int MAX_Y_COORD    = 128,
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

    output graph_pkg::event_type                             pos_item,
    output graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] edges
);

    graph_pkg::event_type event_normalized;
    logic                 reset_context;

/////////////////////////////////////////////////////////////////
//                          NORMALIZE                          //
// Scale X and Y, Quantize and normalize t based on GRAPH_SIZE //
/////////////////////////////////////////////////////////////////

    normalize #(
        .MAX_X_COORD    ( MAX_X_COORD            ),
        .MAX_Y_COORD    ( MAX_Y_COORD            ),
        .GRAPH_SIZE     ( graph_pkg::GRAPH_SIZE  ),
        .INPUT_BIT_TIME ( INPUT_BIT_TIME         ),
        .INPUT_BIT_X    ( INPUT_BIT_X            ),
        .INPUT_BIT_Y    ( INPUT_BIT_X            ),
        .TIME_WINDOW    ( graph_pkg::TIME_WINDOW )
    ) u_normalize       (
        .clk            ( clk              ),
        .reset          ( reset            ),
        .timestamp      ( timestamp        ),
        .x_coord        ( x_coord          ),
        .y_coord        ( y_coord          ),
        .polarity       ( polarity         ),
        .is_valid       ( is_valid         ),
        .out_event      ( event_normalized ),
        .reset_context  ( reset_context    )
    );

/////////////////////////////////////////////////////////////////
//                          EDGES GEN                          //
// Generate edges besed on Context read from memory, update it //
/////////////////////////////////////////////////////////////////

    edges_gen #(
        .GRAPH_SIZE  ( graph_pkg::GRAPH_SIZE  ),
        .RADIUS      ( graph_pkg::RADIUS      ),
        .TIME_WINDOW ( graph_pkg::TIME_WINDOW )
    ) u_edges_gen (
        .clk           ( clk              ),
        .reset         ( reset            ),
        .in_event      ( event_normalized ),
        .out_event     ( pos_item         ),
        .edges         ( edges            ),
        .reset_context ( reset_context    )
    );

endmodule : generate_graph
