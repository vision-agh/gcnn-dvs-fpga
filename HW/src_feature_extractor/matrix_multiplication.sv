`timescale 1ns / 1ps

module matrix_multiplication #(
    parameter int INPUT_DIM = 4,
    parameter int OUTPUT_DIM = 8,
    parameter int PRECISION = 8,
    parameter int MULTIPLIER = 0,
    parameter int ZERO_POINT = 0
)( 
    input  logic                        clk,
    input  logic                        reset,
    input  logic signed [PRECISION:0]   feature_matrix [INPUT_DIM-1:0],
    input  logic signed [PRECISION:0]   weight_matrix  [OUTPUT_DIM-1:0][INPUT_DIM-1:0],
    input  logic signed [31:0]          bias           [OUTPUT_DIM-1:0],
    output logic        [PRECISION-1:0] output_matrix  [OUTPUT_DIM-1:0]
);

    logic signed [31:0]        matrix_result  [OUTPUT_DIM-1:0];
    logic signed [63:0]        debug_bias  [OUTPUT_DIM-1:0];
    logic signed [63:0]        debug_mul  [OUTPUT_DIM-1:0];

    genvar m;

    generate
        for (m = 0; m < OUTPUT_DIM; m++) begin : raw
            always @(posedge clk) begin
                matrix_result[m] = 0;
                for (int j=0; j< INPUT_DIM; j=j+1) begin: cols
                    matrix_result[m] = matrix_result[m] + (feature_matrix[j] * weight_matrix[m][j]);
                end
                debug_bias[m] <= (matrix_result[m]+bias[m]);
            end
            always @(posedge clk) begin
                debug_mul[m] = (debug_bias[m]*MULTIPLIER)>>>32;
                output_matrix[m] <= debug_mul[m][31:0] + ZERO_POINT;
            end
        end
    endgenerate

endmodule
