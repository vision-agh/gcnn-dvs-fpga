module feature_memory #(
    parameter int GRAPH_SIZE  = 32,
    parameter int PRECISION	  = graph_pkg::PRECISION,
    parameter int FEATURE_DIM = 16,
    parameter int ADDR_WIDTH  = $clog2(GRAPH_SIZE*GRAPH_SIZE),
    parameter int DATA_WIDTH  = (FEATURE_DIM*PRECISION) + (9*2), //edges
    parameter RAM_TYPE        = "block"
)( 
    input logic	                       clk,
    input logic	                       reset,

    output logic [DATA_WIDTH-1 : 0]    in_read,
    input  logic [DATA_WIDTH-1 : 0]    in_write,
    input  logic [ADDR_WIDTH-1 : 0]	   in_addr,
    input  logic                       in_ena,
    input  logic                       in_wea,
    input  logic [1:0]                 in_mem_ptr,

    output logic [DATA_WIDTH-1 : 0]    out_read_a,
    output logic [DATA_WIDTH-1 : 0]    out_read_b,
    input  logic [ADDR_WIDTH-1 : 0]    out_addr,

    input  logic                       out_clean,
    output logic                       out_switch
);

    logic [ADDR_WIDTH-1:0] addra [2:0];
    logic [ADDR_WIDTH-1:0] addrb [2:0];
    logic [DATA_WIDTH-1:0] dina  [2:0];
    logic [DATA_WIDTH-1:0] douta [2:0];
    logic [DATA_WIDTH-1:0] doutb [2:0];
    logic ena [2:0];
    logic wea [2:0];
    logic enb [2:0];
    logic out_clean_0;
    logic out_clean_1;
    logic out_clean_2;

    logic [1:0] in_mem_ptr_reg;
    logic [ADDR_WIDTH-1:0] clean_addr;

    always @(posedge clk) begin
        if (reset) begin
            clean_addr <= '0;
        end
        if (out_clean) begin
            if (clean_addr < (GRAPH_SIZE*GRAPH_SIZE)) begin
                clean_addr <= clean_addr + 1;
            end
            else begin
                clean_addr <= '0;
            end
        end
        in_mem_ptr_reg <= in_mem_ptr;
    end

    assign out_switch = (in_mem_ptr_reg != in_mem_ptr);

    // PORT A - Read/write on in_side, zero on out_side
    assign ena[0] = (in_mem_ptr == 0) ? in_ena : out_clean_0;
    assign wea[0] = (in_mem_ptr == 0) ? in_wea : out_clean_0;
    assign ena[1] = (in_mem_ptr == 1) ? in_ena : out_clean_1;
    assign wea[1] = (in_mem_ptr == 1) ? in_wea : out_clean_1;
    assign ena[2] = (in_mem_ptr == 2) ? in_ena : out_clean_2;
    assign wea[2] = (in_mem_ptr == 2) ? in_wea : out_clean_2;

    assign addra[0] = (in_mem_ptr == 0) ? in_addr : clean_addr;
    assign addra[1] = (in_mem_ptr == 1) ? in_addr : clean_addr;
    assign addra[2] = (in_mem_ptr == 2) ? in_addr : clean_addr;

    assign dina[0] = (in_mem_ptr == 0) ? in_write : '0;
    assign dina[1] = (in_mem_ptr == 1) ? in_write : '0;
    assign dina[2] = (in_mem_ptr == 2) ? in_write : '0;

    assign in_read = (in_mem_ptr == 0) ? douta[0] : (in_mem_ptr == 1) ? douta[1] : douta[2];

    assign out_clean_0 = out_clean && (in_mem_ptr == 2);
    assign out_clean_1 = out_clean && (in_mem_ptr == 0);
    assign out_clean_2 = out_clean && (in_mem_ptr == 1);

    // PORT B - Read on out_side
    assign out_read_a = (in_mem_ptr == 0) ? doutb[2] : ((in_mem_ptr == 1) ? doutb[0] : doutb[1]);
    assign out_read_b = (in_mem_ptr == 0) ? doutb[1] : ((in_mem_ptr == 1) ? doutb[2] : doutb[0]);
    assign enb[0] = (in_mem_ptr != 0) & !out_clean;
    assign enb[1] = (in_mem_ptr != 1) & !out_clean;
    assign enb[2] = (in_mem_ptr != 2) & !out_clean;

    memory #(
        .AWIDTH   ( ADDR_WIDTH ),
        .DWIDTH   ( DATA_WIDTH ),
        .RAM_TYPE ( RAM_TYPE   )
    ) feature_0   (
        .clk      ( clk      ),
        .mem_ena  ( ena[0]   ),
        .wea      ( wea[0]   ),
        .addra    ( addra[0] ),
        .dina     ( dina[0]  ),
        .douta    ( douta[0] ),
        .mem_enb  ( enb[0]   ),
        .web      ( '0       ),
        .addrb    ( out_addr ),
        .doutb    ( doutb[0] )
    );

    memory #(
        .AWIDTH   ( ADDR_WIDTH ),
        .DWIDTH   ( DATA_WIDTH ),
        .RAM_TYPE ( RAM_TYPE   )
    ) feature_1   (
        .clk      ( clk      ),
        .mem_ena  ( ena[1]   ),
        .wea      ( wea[1]   ),
        .addra    ( addra[1] ),
        .dina     ( dina[1]  ), 
        .douta    ( douta[1] ),
        .mem_enb  ( enb[1]   ),
        .web      ( '0       ),
        .addrb    ( out_addr ),
        .doutb    ( doutb[1] )
    );

    memory #(
        .AWIDTH   ( ADDR_WIDTH ),
        .DWIDTH   ( DATA_WIDTH ),
        .RAM_TYPE ( RAM_TYPE   )
    ) feature_2   (
        .clk      ( clk      ),
        .mem_ena  ( ena[2]   ),
        .wea      ( wea[2]   ),
        .addra    ( addra[2] ),
        .dina     ( dina[2]  ), 
        .douta    ( douta[2] ),
        .mem_enb  ( enb[2]   ),
        .web      ( '0       ),
        .addrb    ( out_addr ),
        .doutb    ( doutb[2] )
    );

endmodule