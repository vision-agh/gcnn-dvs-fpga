module feature_memory_simple #(
    parameter int GRAPH_SIZE  = 32,
    parameter int PRECISION	  = graph_pkg::PRECISION,
    parameter int FEATURE_DIM = 16,
    parameter int ADDR_WIDTH  = $clog2(GRAPH_SIZE*GRAPH_SIZE),
    parameter int ADDR_WIDTH_OUT = $clog2(GRAPH_SIZE*GRAPH_SIZE*3)+1,
    parameter int DATA_WIDTH  = (FEATURE_DIM*PRECISION) + (9*2), //edges
    parameter RAM_TYPE        = "block"
)( 
    input logic	                       clk,
    input logic	                       reset,

    output logic [DATA_WIDTH-1 : 0]     in_read,
    input  logic [DATA_WIDTH-1 : 0]     in_write,
    input  logic [ADDR_WIDTH-1 : 0]	    in_addr,
    input  logic                        in_ena,
    input  logic                        in_wea,
    input  logic [1:0]                  in_mem_ptr,

    output logic [DATA_WIDTH-1 : 0]     out_read,
    input  logic [ADDR_WIDTH_OUT-1 : 0] out_addr,
    input  logic                        out_valid,

    input  logic                        out_clean,
    input  logic [1:0]                  out_mem_ptr,
    output logic                        out_switch
);

    logic [ADDR_WIDTH_OUT-1:0] addra;
    logic [ADDR_WIDTH_OUT-1:0] addrb;

    logic [1:0] in_mem_ptr_reg;
    logic [ADDR_WIDTH-1:0] clean_addr;
    logic [1:0]            clean_ptr;
    
    assign clean_ptr = (out_mem_ptr == 0) ? 2'd2 : (out_mem_ptr == 1) ? 2'd0 : 2'd1;

    always @(posedge clk) begin
        if (reset) begin
            clean_addr <= '0;
        end
        clean_addr <= '0;
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

    assign addra = (in_mem_ptr*(GRAPH_SIZE*GRAPH_SIZE)) + in_addr;
    assign addrb = out_clean ? (clean_addr + (clean_ptr*(GRAPH_SIZE*GRAPH_SIZE))) : out_addr;

    memory #(
        .AWIDTH   ( ADDR_WIDTH_OUT ),
        .DWIDTH   ( DATA_WIDTH     ),
        .RAM_TYPE ( RAM_TYPE       )
    ) feature_0   (
        .clk      ( clk                    ),
        .mem_ena  ( in_ena                 ),
        .wea      ( in_wea                 ),
        .addra    ( addra                  ),
        .dina     ( in_write               ),
        .douta    ( in_read                ),
        .mem_enb  ( out_valid || out_clean ),
        .web      ( out_clean              ),
        .addrb    ( addrb                  ),
        .dinb     ( '0                     ),
        .doutb    ( out_read               )
    );

endmodule