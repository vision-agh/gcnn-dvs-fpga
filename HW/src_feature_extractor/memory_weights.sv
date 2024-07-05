`timescale 1ns / 1ps

//  Based on Language Templates - URAM/BRAM Memory
//  Xilinx UltraRAM True Dual Port Mode.

module memory_weights #(
    parameter AWIDTH   = 16,     // Address Width
    parameter DWIDTH   = 72,     // Data Width
    parameter RAM_TYPE = "ultra", // Memory type ("ultra" or "block"
    parameter string INIT_PATH = "/home/power-station/Repo/Event2Graph/mem/tiny_conv2_param.mem"
) ( 
    input                     clk,
    input                     read,
    input [AWIDTH-1:0]        addr,
    output logic [DWIDTH-1:0] dout
);

    (* ram_style = RAM_TYPE *) logic [DWIDTH-1:0] mem[(1<<AWIDTH)-1:0]; // Memory Declaration
    initial begin
        $readmemh(INIT_PATH, mem);
    end
      
    // RAM : Read has one latency, Write has one latency as well.
    always @ (posedge clk) begin
        if (read) begin
            dout <= mem[addr];
        end     
    end

endmodule
