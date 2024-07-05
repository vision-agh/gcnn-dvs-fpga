`timescale 1ns / 1ps

module async_conv #(
    parameter int GRAPH_SIZE        = graph_pkg::GRAPH_SIZE,
    parameter int PRECISION	        = graph_pkg::PRECISION,
    parameter int INPUT_DIM         = 4,
    parameter int OUTPUT_DIM        = 16,
    parameter int MULTIPLIER_OUT    = 28877700,
    parameter int ZERO_POINT        = 126,
    parameter int SCALE_IN [2:0]    = {0, 0, 0}
)( 
    input  logic                                             clk,
    input  logic                                             reset,
    input  graph_pkg::event_type                             in_event,
    input  graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] in_edges,

    input logic signed [PRECISION:0]                         weights [OUTPUT_DIM-1:0][INPUT_DIM-1:0],
    input logic signed [31:0]                                bias [15:0],

    output graph_pkg::event_type                             out_event,
    output graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] out_edges,
    output logic        [PRECISION-1 :0]                     features [OUTPUT_DIM-1 : 0]
);
    localparam GRAPH_WIDTH    = $clog2(GRAPH_SIZE);
    localparam MEMORY_OPS_NUM = graph_pkg::MEMORY_OPS_NUM;
    
    // Relative position input feature quantization parameters
    localparam logic signed [PRECISION:0] NEG_3 = -SCALE_IN[2];
    localparam logic signed [PRECISION:0] NEG_2 = -SCALE_IN[1];
    localparam logic signed [PRECISION:0] NEG_1 = -SCALE_IN[0];
    localparam logic signed [PRECISION:0] POS_1 = SCALE_IN[0];
    localparam logic signed [PRECISION:0] POS_2 = SCALE_IN[1];
    localparam logic signed [PRECISION:0] POS_3 = SCALE_IN[2];

    // Context for vertex edges parameters
    localparam logic signed [PRECISION:0] FEATURES_A_X [MEMORY_OPS_NUM-1:0] = {0, NEG_1, NEG_2, NEG_3, POS_2,  POS_1, 0, NEG_1, NEG_2, POS_2,  POS_1, 0, NEG_1, NEG_2, 0};
    localparam logic signed [PRECISION:0] FEATURES_B_X [MEMORY_OPS_NUM-1:0] = {0, POS_2, POS_1, 0, NEG_1, NEG_2, POS_2, POS_1, 0, NEG_1, NEG_2, POS_3, POS_2, POS_1, 0};
    localparam logic signed [PRECISION:0] FEATURES_B_Y [MEMORY_OPS_NUM-1:0] = {POS_3, POS_2, POS_2, POS_2, POS_2, POS_2, POS_1, POS_1, POS_1, POS_1, POS_1, 0, 0, 0, 0};
    localparam logic signed [PRECISION:0] FEATURES_A_Y [MEMORY_OPS_NUM-1:0] = {0, 0, 0, 0, NEG_1, NEG_1, NEG_1, NEG_1, NEG_1, NEG_2, NEG_2, NEG_2, NEG_2, NEG_2, NEG_3};

    graph_pkg::event_type                             temp_event;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] temp_edges;
    graph_pkg::event_type                             reg_event;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] reg_edges;
    graph_pkg::event_type                             h1_event;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] h1_edges;
    graph_pkg::event_type                             h2_event;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] h2_edges;

    logic [$clog2(MEMORY_OPS_NUM)-1 : 0] counter;
    logic [$clog2(MEMORY_OPS_NUM)-1 : 0] counter_h1;
    logic [$clog2(MEMORY_OPS_NUM)-1 : 0] counter_h2;
    logic [$clog2(MEMORY_OPS_NUM)-1 : 0] counter_reg;
    logic [$clog2(MEMORY_OPS_NUM)-1 : 0] counter_out;

    logic signed [PRECISION:0] feature_mat_a [INPUT_DIM-1:0];
    logic signed [PRECISION:0] feature_mat_b [INPUT_DIM-1:0];

    logic [PRECISION-1:0] output_mat_a [OUTPUT_DIM-1:0];
    logic [PRECISION-1:0] output_mat_b [OUTPUT_DIM-1:0];
    logic [PRECISION-1:0] output_mat   [OUTPUT_DIM-1:0];

    // Counters control, input data assignments
    always @(posedge clk) begin
        if (reset) begin
            counter <= 0;
            counter_reg <= 0;
            counter_h1 <= '0;
            counter_h2 <= '0;
            counter_out <= '0;
        end
        else begin
            counter_h1 <= counter;
            counter_h2 <= counter_h1;
            counter_reg <= counter_h2;
            counter_out <= counter_reg;
            if (in_event.valid) begin
                temp_event <= in_event;
                temp_edges <= in_edges;
                counter <= 0;
            end
            if (counter < MEMORY_OPS_NUM-1) begin
                counter <= counter +1;
            end
        end
    end
    
    // Port A
    always @(posedge clk) begin
        feature_mat_a[0] <= (counter==MEMORY_OPS_NUM-1) ? (temp_event.p * POS_1) : (temp_edges[counter].attribute * POS_1);
        feature_mat_a[1] <= FEATURES_A_X[counter];
        feature_mat_a[2] <= FEATURES_A_Y[counter];
        feature_mat_a[3] <= (counter==MEMORY_OPS_NUM-1) ? 0 : (temp_edges[counter].t == 1 ? NEG_1 : (temp_edges[counter].t == 2 ? NEG_2 : (temp_edges[counter].t == 3 ? NEG_3 : 0)));
    end

    matrix_multiplication #(
        .INPUT_DIM         ( INPUT_DIM         ),
        .OUTPUT_DIM        ( OUTPUT_DIM        ),
        .MULTIPLIER        ( MULTIPLIER_OUT    ),
        .ZERO_POINT        ( ZERO_POINT        )
    ) mul_a (
        .clk             ( clk             ),
        .reset           ( reset           ),
        .feature_matrix  ( feature_mat_a   ),
        .bias            ( bias            ),
        .weight_matrix   ( weights         ),
        .output_matrix   ( output_mat_a    )
    );

    // PORT B
    always @(posedge clk) begin
       feature_mat_b[0] <= temp_edges[MEMORY_OPS_NUM-1+counter].attribute * POS_1;
       feature_mat_b[1] <= FEATURES_B_X[counter];
       feature_mat_b[2] <= FEATURES_B_Y[counter]; 
       feature_mat_b[3] <= (temp_edges[MEMORY_OPS_NUM-1+counter].t == 1 ? NEG_1 : (temp_edges[MEMORY_OPS_NUM-1+counter].t == 2 ? NEG_2 : (temp_edges[MEMORY_OPS_NUM-1+counter].t == 3 ? NEG_3 : 0)));
    end

    matrix_multiplication #(
        .INPUT_DIM         ( INPUT_DIM         ),
        .OUTPUT_DIM        ( OUTPUT_DIM        ),
        .MULTIPLIER        ( MULTIPLIER_OUT    ),
        .ZERO_POINT        ( ZERO_POINT        )
    ) mul_b (
        .clk             ( clk             ),
        .reset           ( reset           ),
        .feature_matrix  ( feature_mat_b   ),
        .bias            ( bias            ),
        .weight_matrix   ( weights         ),
        .output_matrix   ( output_mat_b    )
    );

    // Features calculation (including ReLU activation)
    logic [1:0] condition;
    assign condition = {reg_edges[MEMORY_OPS_NUM-1+counter_reg].is_connected, (reg_edges[counter_reg].is_connected || counter_reg==MEMORY_OPS_NUM-1)};
    genvar i;
    generate
        for (i = 0; i < OUTPUT_DIM; i++) begin : rows
            always @(posedge clk) begin
                output_mat[i] <= condition == 2'b11 ? (output_mat_a[i] > output_mat_b[i] ? output_mat_a[i] : output_mat_b[i]) : 
                                                      (condition == 2'b00 ? 8'b00000000 : (condition == 2'b01 ? output_mat_a[i] : output_mat_b[i]));
                if (counter_out == 0) begin
                    features[i] <= ZERO_POINT > output_mat[i] ? ZERO_POINT : output_mat[i];
                end
                else begin
                    features[i] <= features[i] > output_mat[i] ? features[i] : output_mat[i];
                end
            end
        end
    endgenerate

    // Output control, valid delay
    logic valid_d1;
    
    delay_module #(
        .N        ( 1  ),
        .DELAY    ( 19 )
    ) delay_valid_2 (
        .clk   ( clk            ),
        .idata ( in_event.valid ),
        .odata ( valid_d1       )
    );

    graph_pkg::event_type				              out_reg_event;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] out_reg_edges;

    always @(posedge clk) begin
        h1_event <= temp_event;
        h1_edges <= temp_edges;
        h2_event <= h1_event;
        h2_edges <= h1_edges;
        reg_event <= h2_event;
        reg_edges <= h2_edges;
        out_reg_event <= reg_event;
        out_reg_edges <= reg_edges;
        out_event <= out_reg_event;
        out_edges <= out_reg_edges;
        out_event.valid <= valid_d1;
    end

endmodule
