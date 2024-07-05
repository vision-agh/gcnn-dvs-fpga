`timescale 1ns / 1ps

module vector_multiplication #(
    parameter int INPUT_DIM = 4,
    parameter int PRECISION = 8,
    parameter int MULTIPLIER = 0,
    parameter int ZERO_POINT = 0
)( 
    input  logic                        clk,
    input  logic                        reset,
    input  logic signed [PRECISION:0]   feature_matrix [INPUT_DIM-1:0],
    input  logic signed [PRECISION:0]   weight_matrix  [INPUT_DIM-1:0],
    input  logic signed [31:0]          bias,
    output logic        [PRECISION-1:0] output_matrix  
);

    localparam PARALLEL = INPUT_DIM / 4;

    logic signed [31:0]        matrix_result [PARALLEL : 0];
    logic signed [31:0]        matrix_result_reg [PARALLEL : 0];
    logic signed [63:0]        debug_bias ;
    logic signed [63:0]        debug_mul;
    logic signed [31:0]        bias_reg;

    genvar p;
    generate
        for (p = 0; p < PARALLEL; p++) begin : multiply
            always @(posedge clk) begin
                matrix_result[p] = 0;
                for (int j=(4*p); j<(4*(p+1)); j=j+1) begin: cols
                    matrix_result[p] = matrix_result[p] + (feature_matrix[j] * weight_matrix[j]);
                end
                matrix_result_reg[p] <= matrix_result[p];
            end
        end
    endgenerate

    always @(posedge clk) begin
        matrix_result[PARALLEL] = 0;
        for (int j=INPUT_DIM-3; j<INPUT_DIM; j=j+1) begin: cols
            matrix_result[PARALLEL] = matrix_result[PARALLEL] + (feature_matrix[j] * weight_matrix[j]);
        end
        matrix_result_reg[PARALLEL] <= matrix_result[PARALLEL];
    end

    always @(posedge clk) begin
        debug_bias = bias_reg;
        for (int i=0; i<= PARALLEL; i++) begin
            debug_bias = debug_bias + matrix_result_reg[i];
        end
        debug_mul <= debug_bias;
        output_matrix <= ((debug_mul*MULTIPLIER)>>>32) + ZERO_POINT;
        bias_reg <= bias;
    end

endmodule

