`timescale 1ns / 1ps

module delay_module #(
    parameter N=4,
    parameter DELAY=2
)(
    input          clk,
    input  [N-1:0] idata,
    output [N-1:0] odata
);

    wire [N-1:0] tdata [DELAY:0];
    assign tdata[0]=idata;
    
    genvar i;
    generate
        if(DELAY==0) assign odata = idata;
        else if(DELAY>0) begin
            for (i=0;i<DELAY;i=i+1) begin    
                delay_single #(
                    .N ( N )
                ) delaygau (
                    .clk   ( clk       ),
                    .idata ( tdata[i]  ),
                    .odata ( tdata[i+1])
                );
            end
        end
    endgenerate
    
    assign odata = tdata[DELAY];

endmodule