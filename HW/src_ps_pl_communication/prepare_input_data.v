`timescale 1ns / 1ps

module prepare_input_data(
    input clk,    
    output [31:0]timestamp,
    output [7:0]x,
    output [7:0]y,
    output polarity,
    output is_valid,    
    input [31:0]axi_data_in,
    input [11:0]axi_addr_in,
    input axi_en,
    input axi_we,        
    output resetn
);

    reg [9:0]addr = 0;
    reg r_reset = 0;
    reg init = 1;
    reg timest = 0;
    reg [31:0]r_data1 = 0;
    reg [31:0]r_data2 = 0;
    reg [31:0]r_data3 = 0;
    
    // Add 3 registers layers for path timings
    reg [31:0]timestamp_reg;
    reg [7:0]x_reg;
    reg [7:0]y_reg;
    reg polarity_reg;
    reg is_valid_reg;
    reg resetn_reg;

    reg [31:0]timestamp_reg2;
    reg [7:0]x_reg2;
    reg [7:0]y_reg2;
    reg polarity_reg2;
    reg is_valid_reg2;
    reg resetn_reg2;

    always @(posedge clk) begin
        if(axi_en)
            timest <= ~timest;
        r_data1 <= axi_data_in;
        r_data2 <= r_data1;
        r_data3 <= r_data2;    
        addr <= addr + 1;
    
        if(init == 1 && addr == 1000)
            r_reset <= 1;
        if(r_reset == 1 && addr == 1023) begin
            r_reset <= 0;
            init <= 0;
        end
        timestamp_reg <=  timest ? axi_data_in[31:0] : 0;
        x_reg <= timest ? r_data3[17:10] : 0;
        y_reg <= timest ? r_data3[9:2] : 0;
        polarity_reg <= timest ? r_data3[1] : 0;
        is_valid_reg <= timest ? axi_we : 0;
        resetn_reg <= r_reset;
        
        timestamp_reg2 <= timestamp_reg;
        x_reg2 <= x_reg;
        y_reg2 <= y_reg;
        polarity_reg2 <= polarity_reg;
        is_valid_reg2 <= is_valid_reg;
        resetn_reg2 <= resetn_reg;
        
    end

    assign timestamp = timestamp_reg2;
    assign x = x_reg2;
    assign y = y_reg2;
    assign polarity = polarity_reg2;
    assign is_valid = is_valid_reg2;
    assign resetn = resetn_reg2;

endmodule
