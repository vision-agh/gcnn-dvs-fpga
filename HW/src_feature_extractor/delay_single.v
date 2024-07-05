`timescale 1ns / 1ps

module delay_single #(
    parameter N=4
)(
    input          clk,
    input  [N-1:0] idata,
    output [N-1:0] odata
);

    reg [N-1:0] val = 0;
    always @(posedge clk) begin
        val<=idata;
    end
    
    assign odata=val;

endmodule
