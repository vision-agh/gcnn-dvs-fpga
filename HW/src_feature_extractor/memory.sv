`timescale 1ns / 1ps

//  Based on Language Templates - URAM/BRAM Memory
//  Xilinx UltraRAM True Dual Port Mode.

module memory #(
    parameter AWIDTH   = 16,     // Address Width
    parameter DWIDTH   = 72,     // Data Width
    parameter RAM_TYPE = "ultra" // Memory type ("ultra" or "block")
) ( 
    input                     clk,     // Clock

    // Port A
    input                     wea,     // Write Enable
    input                     mem_ena, // Memory Enable
    input [DWIDTH-1:0]        dina,    // Data Input  
    input [AWIDTH-1:0]        addra,   // Address Input
    output logic [DWIDTH-1:0] douta,   // Data Output

    // Port B
    input                     web,     // Write Enable
    input                     mem_enb, // Memory Enable
    input [DWIDTH-1:0]        dinb,    // Data Input  
    input [AWIDTH-1:0]        addrb,   // Address Input
    output logic [DWIDTH-1:0] doutb    // Data Output
);

    (* ram_style = RAM_TYPE *) reg [DWIDTH-1:0] mem [(1<<AWIDTH)-1:0] = '{default:0}; // Memory Declaration
    
    // RAM : Read has one latency, Write has one latency as well.
    always @ (posedge clk) begin
        if (mem_ena) begin
            if (wea) mem[addra] <= dina;
            else     douta <= mem[addra];
        end     
    end
    
    // RAM : Read has one latency, Write has one latency as well.
    always @ (posedge clk) begin
        if (mem_enb) begin
            if(web) mem[addrb] <= dinb;
            else    doutb <= mem[addrb];
        end     
    end

endmodule
