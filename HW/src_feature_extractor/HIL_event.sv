`timescale 1ns / 1ps

module HIL_event #(
    parameter int MAX_X_COORD    = 128,
    parameter int MAX_Y_COORD    = 128,
    parameter int GRAPH_SIZE     = 128,
    parameter int INPUT_BIT_TIME = 34,
    parameter int INPUT_BIT_X    = 14,
    parameter int INPUT_BIT_Y    = 14,
    parameter int COUNTER_WIDTH  = 9,
    parameter int TIME_WINDOW    = 50000
)( 
    input logic                        clk,
    input logic                        reset,
    input logic [INPUT_BIT_TIME-1: 0]  timestamp,
    input logic [INPUT_BIT_X-1 : 0]    x_coord,
    input logic [INPUT_BIT_Y-1 : 0]    y_coord,
    input logic                        polarity,
    input logic                        is_valid,

    output graph_pkg::event_type       out_event,
    output logic [COUNTER_WIDTH-1 : 0] window_counter
);


    localparam ADDR_WIDTH = $clog2(2048);
    localparam DATA_WIDTH = 64;
    localparam INIT_PATH = "/home/pwz/Documents/events_hex.mem";

    logic [INPUT_BIT_TIME-1: 0]  event_t;
    logic [INPUT_BIT_X-1 : 0]    event_x;
    logic [INPUT_BIT_Y-1 : 0]    event_y;
    logic                        event_p;

    logic [ADDR_WIDTH-1 : 0]  	 addr_counter = 0;
    logic [DATA_WIDTH-1 : 0]     weight_mem;
    logic [INPUT_BIT_TIME-1: 0]  timestamp_cnt = 0;
    logic [INPUT_BIT_TIME-1: 0]  time_to_normalize = 0;
    logic [10 : 0]               clk_cntr = 0;
 
    logic is_first = 1;

    localparam IDLE = 1'b0;
    localparam GEN = 1'b1;
    logic state = IDLE;
    logic state_reg = IDLE;

    graph_pkg::event_type        register;

    memory_weights #(
        .AWIDTH   ( ADDR_WIDTH ),
        .DWIDTH   ( DATA_WIDTH ),
        .RAM_TYPE ( "block"        ),
        .INIT_PATH ( INIT_PATH     )
    ) weights_memory   (
        .clk      ( clk      ),
        .read     ( state == GEN    ),
        .addr     ( addr_counter    ),
        .dout     ( weight_mem      )
    );


    assign event_t = weight_mem[33:0];
    assign event_p = weight_mem[34];
    assign event_y = weight_mem[48:35];
    assign event_x = weight_mem[63:49];

    always @(posedge clk) begin
        if (reset) begin
            is_first <= 1;
            state <= IDLE;
            addr_counter <= '0;
            clk_cntr <= '0;
            timestamp_cnt <= '0;
            window_counter <= '0;
        end
        else begin
            if (is_valid) begin
            	state <= GEN;
            end
            if (state == GEN) begin
            	// Handle counter
                clk_cntr <= clk_cntr+5;
                if (clk_cntr >= 1000) begin
                    timestamp_cnt <= timestamp_cnt+1;
                    clk_cntr <= '0;
                end
            end
            register.x <= event_x;
            register.y <= event_y;
            register.p <= event_p;
            time_to_normalize <= event_t + window_counter*100000;
            register.valid <= 1'b0;
            if (state_reg == GEN && !register.valid) begin
            	if ((event_t + window_counter*100000) <= timestamp_cnt) begin
            		register.valid <= 1'b1;
	            	addr_counter <= addr_counter + 1;
	            	if (addr_counter == 1938) begin
	            		addr_counter <= '0;
	            		window_counter <= window_counter+1;
	            	end
            	end
            end
            state_reg <= state;
            out_event <= register;
            out_event.t <= ((time_to_normalize % TIME_WINDOW) * GRAPH_SIZE)/TIME_WINDOW;
        end
    end


endmodule : HIL_event