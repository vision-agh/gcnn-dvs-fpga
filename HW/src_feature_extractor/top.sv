`timescale 1ns / 1ps

module top #(
    parameter int MAX_X_COORD	 = 128,
    parameter int MAX_Y_COORD	 = 128,
    parameter int INPUT_BIT_TIME = 32,
    parameter int INPUT_BIT_X    = 8,
    parameter int INPUT_BIT_Y    = 8,
    parameter int DATA_WIDTH_MAXPOOL1 = (16*graph_pkg::PRECISION) + (9*2),
    parameter int ADDR_WIDTH_MAXPOOL1 = $clog2(32*32),
    parameter int ADDR_WIDTH_MAXPOOL2 = $clog2(16*16),
    parameter int DATA_WIDTH_CONV2 = (32*graph_pkg::PRECISION) + (9*2),
    parameter int DATA_WIDTH_CONV4 = (64*graph_pkg::PRECISION) + (9*2),
    parameter int ADDR_WIDTH_MAXPOOL3 = $clog2(4*4)
)( 
    input logic                       clk,
    input logic                       reset,
    input logic [INPUT_BIT_TIME-1: 0] timestamp,
    input logic [INPUT_BIT_X-1 : 0]   x_coord,
    input logic [INPUT_BIT_Y-1 : 0]   y_coord,
    input logic                       polarity,
    input logic                       is_valid,

//    output logic                             conv2_wea,
//    output logic [ADDR_WIDTH_MAXPOOL1-1 : 0] conv2_out_addr,
//    output logic [graph_pkg::PRECISION-1 :0] conv2_out_features [31 : 0],
//    output logic [17:0]                      conv2_out_edges,
//    output logic [1:0]                       conv2_mem_ptr

    output logic [$clog2(4*4*4)-1 : 0]        out_addr,
    output logic [graph_pkg::PRECISION-1 : 0] out_data,
    output logic                              out_valid

);
    // GCNN accelerator for MNIST-DVS classification with the following network structure:
    // u_generate_graph     -> graph representation generation with event-by-event updates
    // u_conv1              -> 4 -> 16 convolution for 128x128 graph
    // u_maxpool_1          -> Rescaling graph 128 -> 32
    // u_maxpool_1_mem      -> Memory shared between u_maxpool_1 and u_conv2
    // u_conv2              -> 19 -> 32 convolution for 32x32 graph
    // u_conv2_mem          -> Memory shared between u_conv2 and u_conv3
    // u_conv3              -> 35 -> 32 convolution for 32x32 graph
    // u_maxpool_2          -> Rescaling graph 32 -> 16
    // u_maxpool_2_mem      -> Memory shared between u_maxpool_2 and u_conv4
    // u_conv4              -> 35 -> 64 convolution for 16x16 graph
    // u_conv4_mem          -> Memory shared between u_conv4 and u_conv5
    // u_conv5              -> 67 -> 64 convolution for 16x16 graph
    // u_maxpool_3          -> Rescaling graph 16 -> 4
    // u_maxpool3_mem       -> Memory shared between u_maxpool_3 and u_out_serialize
    // u_out_serialize      -> Output feature map serialization 

    // String paths for weights memories
    localparam string MEMORY_DIR_PATH = {graph_pkg::REPO_PATH, "/HW/mem/"};

    // Parameters for each convolutional layer
    localparam ZERO_POINT_CONV1 = 149;
    localparam MULTIPLIER_OUT_CONV1 = 25508880;
    localparam int SCALE_IN_CONV1 [2:0] = {127, 85, 42};

    localparam ZERO_POINT_IN_CONV2 = ZERO_POINT_CONV1;
    localparam ZERO_POINT_OUT_CONV2 = 200;
    localparam MULTIPLIER_OUT_CONV2 = 40012032;
    localparam SCALE_IN_CONV2 = 35;
    localparam ZERO_POINT_WEIGHT_CONV2 = 190;
    localparam string INIT_PATH_CONV2 = {MEMORY_DIR_PATH, "tiny_conv2_param.mem"};

    localparam ZERO_POINT_IN_CONV3 = ZERO_POINT_OUT_CONV2;
    localparam ZERO_POINT_OUT_CONV3 = 203;
    localparam MULTIPLIER_OUT_CONV3 = 47508080;
    localparam SCALE_IN_CONV3 = 18;
    localparam ZERO_POINT_WEIGHT_CONV3 = 165;
    localparam string INIT_PATH_CONV3 = {MEMORY_DIR_PATH, "tiny_conv3_param.mem"};

    localparam ZERO_POINT_IN_CONV4 = ZERO_POINT_OUT_CONV3;
    localparam ZERO_POINT_OUT_CONV4 = 195;
    localparam MULTIPLIER_OUT_CONV4 = 51488348;
    localparam SCALE_IN_CONV4 = 17;
    localparam ZERO_POINT_WEIGHT_CONV4 = 173;
    localparam string INIT_PATH_CONV4 = {MEMORY_DIR_PATH, "tiny_conv4_param.mem"};

    localparam ZERO_POINT_IN_CONV5 = ZERO_POINT_OUT_CONV4;
    localparam ZERO_POINT_OUT_CONV5 = 213;
    localparam MULTIPLIER_OUT_CONV5 = 71936992;
    localparam SCALE_IN_CONV5 = 13;
    localparam ZERO_POINT_WEIGHT_CONV5 = 199;
    localparam string INIT_PATH_CONV5 = {MEMORY_DIR_PATH, "tiny_conv5_param.mem"};

    /////////////////////////////////////////
    //           GENERATE GRAPH            //
    // Normalize events and generate graph //
    /////////////////////////////////////////

    graph_pkg::event_type                             event_to_conv1;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] edges_to_conv1;

    generate_graph #(
        .MAX_X_COORD    ( MAX_X_COORD    ),
        .MAX_Y_COORD    ( MAX_Y_COORD    ),
        .INPUT_BIT_TIME ( INPUT_BIT_TIME ),
        .INPUT_BIT_X    ( INPUT_BIT_X    ),
        .INPUT_BIT_Y    ( INPUT_BIT_X    )
    ) u_gen_graph       (
        .clk            ( clk            ),
        .reset          ( reset          ),
        .timestamp      ( timestamp      ),
        .x_coord        ( x_coord        ),
        .y_coord        ( y_coord        ),
        .polarity       ( polarity       ),
        .is_valid       ( is_valid       ),
        .pos_item       ( event_to_conv1 ),
        .edges          ( edges_to_conv1 )
    );

    /////////////////////////////////////////
    //         ASYNC CONVOLUTION 1         //
    //            weights 4x16             //
    /////////////////////////////////////////

    logic signed [graph_pkg::PRECISION:0] weights_conv1 [15:0][3:0];
    initial begin
        weights_conv1[0] = {-6, 105, 45, 0};
        weights_conv1[1] = {59, 2, -8, -23};
        weights_conv1[2] = {56, -9, -7, -9};
        weights_conv1[3] = {-3, -103, -47, -1};
        weights_conv1[4] = {-9, -72, 40, 0};
        weights_conv1[5] = {10, -1, -3, 2};
        weights_conv1[6] = {112, 7, -14, -120};
        weights_conv1[7] = {-13, 1, 98, 2};
        weights_conv1[8] = {6, -30, 0, 12};
        weights_conv1[9] = {130, -4, 11, 121};
        weights_conv1[10] = {24, 11, 22, 10};
        weights_conv1[11] = {73, 9, -24, 3};
        weights_conv1[12] = {-17, -16, -98, -2};
        weights_conv1[13] = {56, -4, 4, -3};
        weights_conv1[14] = {18, 18, 11, 17};
        weights_conv1[15] = {-7, 86, -34, -5};
    end

    const logic signed [31:0] bias_conv1 [15:0] = {-3237, -3343, -845, -2419, -3417, -3539, -2513, -4369, -1880, -2075, -439, -1841, -2890, -1806, -2509, -2823};

    logic [graph_pkg::PRECISION-1 :0]                 features_to_maxpool1 [15 : 0];
    graph_pkg::event_type                             event_to_maxpool1;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] edges_to_maxpool1;

   async_conv #(
       .MULTIPLIER_OUT ( MULTIPLIER_OUT_CONV1 ),
       .ZERO_POINT     ( ZERO_POINT_CONV1     ),
       .SCALE_IN       ( SCALE_IN_CONV1       )
   ) u_conv1 (
       .clk       ( clk                   ),
       .reset     ( reset                 ),
       .in_event  ( event_to_conv1        ),
       .in_edges  ( edges_to_conv1        ),
       .weights   ( weights_conv1         ),
       .bias      ( bias_conv1            ),
       .out_event ( event_to_maxpool1     ),
       .out_edges ( edges_to_maxpool1     ),
       .features  ( features_to_maxpool1  )
   );

    ///////////////////////////////////////
    //          ASYNC MAXPOOL 1          //
    ///////////////////////////////////////

    logic [DATA_WIDTH_MAXPOOL1-1 : 0]  read_maxpool1;
    logic [DATA_WIDTH_MAXPOOL1-1 : 0]  write_maxpool1;
    logic [ADDR_WIDTH_MAXPOOL1-1 : 0]  addr_maxpool1;    
    logic                              ena_maxpool1;
    logic                              wea_maxpool1;
    logic [1:0]                        mem_ptr_maxpool1;

    async_maxpool u_maxpool_1 (
       .clk          ( clk                  ),
       .reset        ( reset                ),
       .in_event     ( event_to_maxpool1    ),
       .in_edges     ( edges_to_maxpool1    ),
       .in_features  ( features_to_maxpool1 ),
       .read         ( read_maxpool1        ),
       .write        ( write_maxpool1       ),
       .addr         ( addr_maxpool1        ),
       .ena          ( ena_maxpool1         ),
       .wea          ( wea_maxpool1         ),
       .mem_ptr      ( mem_ptr_maxpool1     )
    );

    /////////////////////////////////////////
    //             FEATURE MEM 1           //
    //          graph 32, feature 16       //
    /////////////////////////////////////////

    logic [DATA_WIDTH_MAXPOOL1-1 : 0] conv2_read_a;
    logic [DATA_WIDTH_MAXPOOL1-1 : 0] conv2_read_b;
    logic [ADDR_WIDTH_MAXPOOL1-1 : 0] conv2_read_addr;
    logic                             conv2_clean;
    logic                             conv2_switch;

    feature_memory u_maxpool_1_mem (
       .clk        ( clk                ),
       .reset      ( reset              ),
       .in_read    ( read_maxpool1      ),
       .in_write   ( write_maxpool1     ),
       .in_addr    ( addr_maxpool1      ),
       .in_ena     ( ena_maxpool1       ),
       .in_wea     ( wea_maxpool1       ),
       .in_mem_ptr ( mem_ptr_maxpool1   ),
       .out_read_a ( conv2_read_a       ),
       .out_read_b ( conv2_read_b       ),
       .out_addr   ( conv2_read_addr    ),
       .out_clean  ( conv2_clean        ),
       .out_switch ( conv2_switch       )
    );

    /////////////////////////////////////////
    //          SYNC CONVOLUTION 2         //
    //            weights 19x32            //
    /////////////////////////////////////////

    logic                             conv2_wea;
    logic [ADDR_WIDTH_MAXPOOL1-1 : 0] conv2_out_addr;
    logic [DATA_WIDTH_CONV2-1 : 0]    conv2_unconnected;
    logic [DATA_WIDTH_CONV2-1 : 0]    conv2_out_data;
    logic [graph_pkg::PRECISION-1 :0] conv2_out_features [31 : 0];
    logic [17:0]                      conv2_out_edges;
    logic [1:0]                       conv2_mem_ptr;

    sync_conv #(
        .ZERO_POINT_IN     ( ZERO_POINT_IN_CONV2     ),
        .ZERO_POINT_OUT    ( ZERO_POINT_OUT_CONV2    ),
        .MULTIPLIER_OUT    ( MULTIPLIER_OUT_CONV2    ),
        .SCALE_IN          ( SCALE_IN_CONV2          ),
        .INIT_PATH         ( INIT_PATH_CONV2         ),
        .ZERO_POINT_WEIGHT ( ZERO_POINT_WEIGHT_CONV2 )
    ) u_conv2 (
        .clk        ( clk                ),
        .reset      ( reset              ),
        .in_data_a  ( conv2_read_a       ),
        .in_data_b  ( conv2_read_b       ),
        .in_addr    ( conv2_read_addr    ),
        .in_clean   ( conv2_clean        ),
        .in_switch  ( conv2_switch       ),
        .out_addr   ( conv2_out_addr     ),
        .out_edges  ( conv2_out_edges    ),
        .features   ( conv2_out_features ),
        .out_valid  ( conv2_wea          ),
        .mem_ptr    ( conv2_mem_ptr      )
    );

    /////////////////////////////////////////
    //             FEATURE MEM 2           //
    //          graph 32, feature 32       //
    /////////////////////////////////////////

    always @(posedge clk) begin
        conv2_out_data[17:0] <= conv2_out_edges;
    end
    genvar j,k;
    generate
        for (k = 0; k < 32; k++) begin : conv2_data_read
            assign conv2_out_data[((graph_pkg::PRECISION*(k+1))-1)+(9*2) : (graph_pkg::PRECISION*k)+(9*2)] = conv2_out_features[k];
        end
    endgenerate

    logic [DATA_WIDTH_CONV2-1 : 0]    conv3_read_a;
    logic [DATA_WIDTH_CONV2-1 : 0]    conv3_read_b;
    logic [ADDR_WIDTH_MAXPOOL1-1 : 0] conv3_read_addr;
    logic                             conv3_clean;
    logic                             conv3_switch;

    feature_memory #(
        .FEATURE_DIM ( 32 )
    ) u_conv2_mem (
       .clk        ( clk                ),
       .reset      ( reset              ),
       .in_read    ( conv2_unconnected  ),
       .in_write   ( conv2_out_data     ),
       .in_addr    ( conv2_out_addr     ),
       .in_ena     ( conv2_wea          ),
       .in_wea     ( conv2_wea          ),
       .in_mem_ptr ( conv2_mem_ptr      ),
       .out_read_a ( conv3_read_a       ),
       .out_read_b ( conv3_read_b       ),
       .out_addr   ( conv3_read_addr    ),
       .out_clean  ( conv3_clean        ),
       .out_switch ( conv3_switch       )
    );

    /////////////////////////////////////////
    //          SYNC CONVOLUTION 3         //
    //            weights 35x32            //
    /////////////////////////////////////////

    logic out_valid_conv3;
    logic [1:0] mem_ptr_conv3;
    logic [ADDR_WIDTH_MAXPOOL1-1 : 0] out_addr_conv3;
    logic [17 : 0] out_edges_conv3;
    logic [7 : 0]  features_conv3 [31 : 0];

    sync_conv #(
        .INPUT_DIM         ( 32                      ),
        .ZERO_POINT_IN     ( ZERO_POINT_IN_CONV3     ),
        .ZERO_POINT_OUT    ( ZERO_POINT_OUT_CONV3    ),
        .MULTIPLIER_OUT    ( MULTIPLIER_OUT_CONV3    ),
        .SCALE_IN          ( SCALE_IN_CONV3          ),
        .INIT_PATH         ( INIT_PATH_CONV3         ),
        .ZERO_POINT_WEIGHT ( ZERO_POINT_WEIGHT_CONV3 )
    ) u_conv3 (
        .clk        ( clk                ),
        .reset      ( reset              ),
        .in_data_a  ( conv3_read_a       ),
        .in_data_b  ( conv3_read_b       ),
        .in_addr    ( conv3_read_addr    ),
        .in_clean   ( conv3_clean        ),
        .in_switch  ( conv3_switch       ),
        .out_addr   ( out_addr_conv3     ),
        .out_edges  ( out_edges_conv3    ),
        .features   ( features_conv3     ),
        .out_valid  ( out_valid_conv3    ),
        .mem_ptr    ( mem_ptr_conv3      )
    );

    /////////////////////////////////////////
    //           SYNC MAXPOOL 2            //
    /////////////////////////////////////////

    logic [DATA_WIDTH_CONV2-1 : 0]    read_maxpool2;
    logic [DATA_WIDTH_CONV2-1 : 0]    write_maxpool2;
    logic [ADDR_WIDTH_MAXPOOL2-1 : 0] addr_maxpool2;    
    logic                             ena_maxpool2;
    logic                             wea_maxpool2;
    logic [1:0]                       mem_ptr_maxpool2;

    sync_maxpool u_maxpool_2 (
       .clk          ( clk                  ),
       .reset        ( reset                ),
       .in_addr      ( out_addr_conv3       ),
       .in_edges     ( out_edges_conv3      ),
       .in_features  ( features_conv3       ),
       .in_valid     ( out_valid_conv3      ),
       .in_mem_ptr   ( mem_ptr_conv3        ),
       .read         ( read_maxpool2        ),
       .write        ( write_maxpool2       ),
       .addr         ( addr_maxpool2        ),
       .ena          ( ena_maxpool2         ),
       .wea          ( wea_maxpool2         ),
       .mem_ptr      ( mem_ptr_maxpool2     )
    );

    /////////////////////////////////////////
    //             FEATURE MEM 3           //
    //          graph 16, feature 32       //
    /////////////////////////////////////////

    logic [DATA_WIDTH_CONV2-1 : 0]    conv4_read_a;
    logic [DATA_WIDTH_CONV2-1 : 0]    conv4_read_b;
    logic [ADDR_WIDTH_MAXPOOL2-1 : 0] conv4_read_addr;
    logic                             conv4_clean;
    logic                             conv4_switch;

    feature_memory #(
        .FEATURE_DIM ( 32 ),
        .GRAPH_SIZE  ( 16 )
    ) u_maxpool2_mem (
       .clk        ( clk                ),
       .reset      ( reset              ),
       .in_read    ( read_maxpool2      ),
       .in_write   ( write_maxpool2     ),
       .in_addr    ( addr_maxpool2      ),
       .in_ena     ( ena_maxpool2       ),
       .in_wea     ( wea_maxpool2       ),
       .in_mem_ptr ( mem_ptr_maxpool2   ),
       .out_read_a ( conv4_read_a       ),
       .out_read_b ( conv4_read_b       ),
       .out_addr   ( conv4_read_addr    ),
       .out_clean  ( conv4_clean        ),
       .out_switch ( conv4_switch       )
    );


    /////////////////////////////////////////
    //          SYNC CONVOLUTION 4         //
    //            weights 35x64            //
    /////////////////////////////////////////

    logic out_valid_conv4;
    logic [1:0] mem_ptr_conv4;
    logic [ADDR_WIDTH_MAXPOOL2-1 : 0] out_addr_conv4;
    logic [17 : 0] out_edges_conv4;
    logic [7 : 0]  features_conv4 [63 : 0];
    logic [DATA_WIDTH_CONV4-1 : 0] conv4_out_data;

    sync_conv #(
        .GRAPH_SIZE        ( 16                      ),
        .INPUT_DIM         ( 32                      ),
        .OUTPUT_DIM        ( 64                      ),
        .ZERO_POINT_IN     ( ZERO_POINT_IN_CONV4     ),
        .ZERO_POINT_OUT    ( ZERO_POINT_OUT_CONV4    ),
        .MULTIPLIER_OUT    ( MULTIPLIER_OUT_CONV4    ),
        .SCALE_IN          ( SCALE_IN_CONV4          ),
        .INIT_PATH         ( INIT_PATH_CONV4         ),
        .ZERO_POINT_WEIGHT ( ZERO_POINT_WEIGHT_CONV4 )
    ) u_conv4 (
        .clk        ( clk                ),
        .reset      ( reset              ),
        .in_data_a  ( conv4_read_a       ),
        .in_data_b  ( conv4_read_b       ),
        .in_addr    ( conv4_read_addr    ),
        .in_clean   ( conv4_clean        ),
        .in_switch  ( conv4_switch       ),
        .out_addr   ( out_addr_conv4     ),
        .out_edges  ( out_edges_conv4    ),
        .features   ( features_conv4     ),
        .out_valid  ( out_valid_conv4    ),
        .mem_ptr    ( mem_ptr_conv4      )
    );

    /////////////////////////////////////////
    //             FEATURE MEM 4           //
    //          graph 16, feature 64       //
    /////////////////////////////////////////

    always @(posedge clk) begin
        conv4_out_data[17:0] <= out_edges_conv4;
    end
    genvar m;
    generate
        for (m = 0; m < 64; m++) begin : conv4_data_read
            assign conv4_out_data[((graph_pkg::PRECISION*(m+1))-1)+(9*2) : (graph_pkg::PRECISION*m)+(9*2)] = features_conv4[m];
        end
    endgenerate

    logic [DATA_WIDTH_CONV4-1 : 0]    conv5_read_a;
    logic [DATA_WIDTH_CONV4-1 : 0]    conv5_read_b;
    logic [ADDR_WIDTH_MAXPOOL2-1 : 0] conv5_read_addr;
    logic                             conv5_clean;
    logic                             conv5_switch;

    feature_memory #(
        .FEATURE_DIM ( 64 ),
        .GRAPH_SIZE  ( 16 )
    ) u_conv4_mem (
       .clk        ( clk                ),
       .reset      ( reset              ),
       .in_read    (                    ),
       .in_write   ( conv4_out_data     ),
       .in_addr    ( out_addr_conv4     ),
       .in_ena     ( out_valid_conv4    ),
       .in_wea     ( out_valid_conv4    ),
       .in_mem_ptr ( mem_ptr_conv4      ),
       .out_read_a ( conv5_read_a       ),
       .out_read_b ( conv5_read_b       ),
       .out_addr   ( conv5_read_addr    ),
       .out_clean  ( conv5_clean        ),
       .out_switch ( conv5_switch       )
    );

    logic out_valid_conv5;
    logic [1:0] mem_ptr_conv5;
    logic [ADDR_WIDTH_MAXPOOL2-1 : 0] out_addr_conv5;
    logic [17 : 0] out_edges_conv5;
    logic [7 : 0]  features_conv5 [63 : 0];

    /////////////////////////////////////////
    //          SYNC CONVOLUTION 5         //
    //            weights 67x64            //
    /////////////////////////////////////////

    sync_conv #(
        .GRAPH_SIZE        ( 16                      ),
        .INPUT_DIM         ( 64                      ),
        .OUTPUT_DIM        ( 64                      ),
        .ZERO_POINT_IN     ( ZERO_POINT_IN_CONV5     ),
        .ZERO_POINT_OUT    ( ZERO_POINT_OUT_CONV5    ),
        .MULTIPLIER_OUT    ( MULTIPLIER_OUT_CONV5    ),
        .SCALE_IN          ( SCALE_IN_CONV5          ),
        .INIT_PATH         ( INIT_PATH_CONV5         ),
        .ZERO_POINT_WEIGHT ( ZERO_POINT_WEIGHT_CONV5 )
    ) u_conv5 (
        .clk        ( clk                ),
        .reset      ( reset              ),
        .in_data_a  ( conv5_read_a       ),
        .in_data_b  ( conv5_read_b       ),
        .in_addr    ( conv5_read_addr    ),
        .in_clean   ( conv5_clean        ),
        .in_switch  ( conv5_switch       ),
        .out_addr   ( out_addr_conv5     ),
        .out_edges  ( out_edges_conv5    ),
        .features   ( features_conv5     ),
        .out_valid  ( out_valid_conv5    ),
        .mem_ptr    ( mem_ptr_conv5      )
    );

    /////////////////////////////////////////
    //           SYNC MAXPOOL 3            //
    /////////////////////////////////////////

    logic [DATA_WIDTH_CONV4-1 : 0]    read_maxpool3;
    logic [DATA_WIDTH_CONV4-1 : 0]    write_maxpool3;
    logic [ADDR_WIDTH_MAXPOOL3-1 : 0] addr_maxpool3;    
    logic                             ena_maxpool3;
    logic                             wea_maxpool3;
    logic [1:0]                       mem_ptr_maxpool3;

    sync_maxpool #(
        .IN_GRAPH_SIZE  ( 16 ),
        .OUT_GRAPH_SIZE ( 4  ),
        .INPUT_DIM      ( 64 )
    ) u_maxpool_3 (
       .clk          ( clk                  ),
       .reset        ( reset                ),
       .in_addr      ( out_addr_conv5       ),
       .in_edges     ( out_edges_conv5      ),
       .in_features  ( features_conv5       ),
       .in_valid     ( out_valid_conv5      ),
       .in_mem_ptr   ( mem_ptr_conv5        ),
       .read         ( read_maxpool3        ),
       .write        ( write_maxpool3       ),
       .addr         ( addr_maxpool3        ),
       .ena          ( ena_maxpool3         ),
       .wea          ( wea_maxpool3         ),
       .mem_ptr      ( mem_ptr_maxpool3     )
    );

    /////////////////////////////////////////
    //             FEATURE MEM 4           //
    //          graph 4, feature 64        //
    /////////////////////////////////////////

    logic [DATA_WIDTH_CONV4-1 : 0]    out_read_a;
    logic [DATA_WIDTH_CONV4-1 : 0]    out_read_b;
    logic [ADDR_WIDTH_MAXPOOL3-1 : 0] out_read_addr;
    logic                             out_clean;
    logic                             out_switch;

    feature_memory #(
        .FEATURE_DIM ( 64 ),
        .GRAPH_SIZE  ( 4  )
    ) u_maxpool3_mem (
       .clk        ( clk                ),
       .reset      ( reset              ),
       .in_read    ( read_maxpool3      ),
       .in_write   ( write_maxpool3     ),
       .in_addr    ( addr_maxpool3      ),
       .in_ena     ( ena_maxpool3       ),
       .in_wea     ( wea_maxpool3       ),
       .in_mem_ptr ( mem_ptr_maxpool3   ),
       .out_read_a ( out_read_a         ),
       .out_read_b (                    ),
       .out_addr   ( out_read_addr      ),
       .out_clean  ( out_clean          ),
       .out_switch ( out_switch         )
    );

    /////////////////////////////////////////
    //          SERIALIZE OUTPUT           //
    /////////////////////////////////////////

    out_serialize #(
        .ZERO_POINT ( ZERO_POINT_OUT_CONV5 )
    ) u_out_serialize (
       .clk       ( clk           ),
       .reset     ( reset         ),
       .in_data   ( out_read_a    ),
       .in_addr   ( out_read_addr ),
       .in_clean  ( out_clean     ),
       .in_switch ( out_switch    ),
       .out_addr  ( out_addr      ),
       .out_data  ( out_data      ),
       .out_valid ( out_valid     )
    );

endmodule : top
