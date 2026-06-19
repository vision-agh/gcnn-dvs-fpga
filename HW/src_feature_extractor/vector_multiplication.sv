`timescale 1ns / 1ps

module vector_multiplication #(
    parameter int INPUT_DIM = 4,
    parameter int PRECISION = graph_pkg::PRECISION,
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

    (* use_dsp = "no" *) logic signed [31:0]        matrix_result [PARALLEL : 0];
    (* use_dsp = "no" *) logic signed [31:0]        matrix_result_reg [PARALLEL : 0];
    (* use_dsp = "no" *) logic signed [31:0]        debug_bias ;
    (* use_dsp = "no" *) logic signed [31:0]        debug_mul;
    logic signed [31:0]        bias_reg;
    logic signed [63:0]        product;
    logic signed [63:0]        product2;

    genvar p;
    generate
        for (p = 0; p < PARALLEL; p++) begin : multiply
            always @(posedge clk) begin
                (* use_dsp = "no" *) matrix_result[p] = 0;
                for (int j=(4*p); j<(4*(p+1)); j=j+1) begin: cols
                    (* use_dsp = "no" *) matrix_result[p] = matrix_result[p] + (feature_matrix[j] * weight_matrix[j]);
                end
                (* use_dsp = "no" *) matrix_result_reg[p] <= matrix_result[p];
            end
        end
    endgenerate

    always @(posedge clk) begin
        (* use_dsp = "no" *) matrix_result[PARALLEL] = 0;
        for (int j=INPUT_DIM-3; j<INPUT_DIM; j=j+1) begin: cols
            (* use_dsp = "no" *) matrix_result[PARALLEL] = matrix_result[PARALLEL] + (feature_matrix[j] * weight_matrix[j]);
        end
        (* use_dsp = "no" *) matrix_result_reg[PARALLEL] <= matrix_result[PARALLEL];
    end

    always @(posedge clk) begin
        (* use_dsp = "no" *) debug_bias = bias_reg;
        for (int i=0; i<= PARALLEL; i++) begin
            (* use_dsp = "no" *) debug_bias = debug_bias + matrix_result_reg[i];
        end
        (* use_dsp = "no" *) debug_mul <= debug_bias;
        product = debug_mul*MULTIPLIER;
        product2 = (product + 32'h8000_0000) >>> 32;
        output_matrix <= product2 + ZERO_POINT;
        bias_reg <= bias;
    end

endmodule

