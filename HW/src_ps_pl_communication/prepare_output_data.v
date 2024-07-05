`timescale 1ns / 1ps

module prepare_output_data(
    input clk,
    input [5:0]addr_in,
    input [7:0]data_in,
    input valid_in,    
    output [9:0]addr_out,
    output [7:0]data_out,
    output en_out,
    output we_out,    
    output read_feature_vector
);

    reg [9:0]cnt = 0;
    reg [9:0]cnt_d = 0;
    reg valid_in_d = 0;
    reg [7:0]data_in_d = 0;
    reg we = 0;
    reg read = 0;
    reg [9:0]addr_out_reg;
    reg [7:0]data_out_reg;
    reg en_out_reg;
    reg we_out_reg;    
    reg read_feature_vector_reg;

    always@(posedge clk) begin
        if(valid_in == 1)
            cnt <= cnt + 1;
        else if(valid_in_d == 1 && valid_in == 0)
            cnt <= 0;
        valid_in_d <= valid_in;
        data_in_d <= data_in;
        we <= valid_in || valid_in_d;
        read <= valid_in == 0 && valid_in_d == 1;
        cnt_d <= cnt;
        addr_out_reg <= cnt;
        data_out_reg <= data_in;
        en_out_reg <= 1'b1;
        we_out_reg <= valid_in || valid_in_d;
        read_feature_vector_reg <= valid_in == 0 && valid_in_d == 1;
        
    end

    assign addr_out = addr_out_reg;
    assign data_out = data_out_reg;
    assign en_out = en_out_reg;
    assign we_out = we_out_reg;
    assign read_feature_vector = read_feature_vector_reg;

endmodule
