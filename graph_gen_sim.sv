`timescale 1ns / 1ps

module example__gen_graph_ut;

    parameter MAX_X_COORD = 128;
    parameter MAX_Y_COORD = 128;
    parameter INPUT_PATH = "//home/pwz/Downloads/JSA-Review/6-bit-mnist-outputs/events.txt";
    parameter OUTPUT_PATH = "/home/pwz/Downloads/JSA-Review/example_conv5_6bit.txt";
    parameter NS_PER_CLK = 5; // 250MHz is 4 clk every ns
    parameter TIME_WINDOW = 100000; // We test only single time window

    logic clk;
    logic rst;
    graph_pkg::event_type pos_item;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] edges;

    logic [graph_pkg::PRECISION-1 :0] features [31 : 0];

    // Queues with values from file
	logic [31: 0]  timestamps [$];
	logic [7 : 0]  x_coords [$];
	logic [7 : 0]  y_coords [$];
	logic	       polarities [$];

    // Values read from queue
	logic [31: 0]  timestamp;
	logic [7 : 0]  x_coord;
	logic [7 : 0]  y_coord;
	logic	       polarity;
	logic [31: 0]  timestamp_reg;
	logic [7 : 0]  x_coord_reg;
	logic [7 : 0]  y_coord_reg;
	logic	       polarity_reg;
	logic          is_valid;
    int node_x;
    int node_y;
    int note_t = 0;
    logic [$clog2(16*16)-1 : 0] out_addr;
    logic [17:0] out_edges;
    logic valid;
    logic [1:0] mem_ptr;
    logic [1:0] mem_ptr_last = 0;


    assign node_x = (out_addr % 16);
    assign node_y = (out_addr - (out_addr % 16)) / 16;

    // Input and output files handler, scheduler.
    int            cnt = 0;
    int            file;
    int            file_out;
    string         line;
    int            current_time_ns;
    string         x_string;
    string         y_string;
    string         t_string;
    string         p_string;

    initial begin
        file = $fopen(INPUT_PATH, "r");
        file_out = $fopen(OUTPUT_PATH, "w");

        while(!$feof(file)) begin
            $fgets(line, file);
            $sscanf (line, "%s %s %s %s", x_string, y_string, t_string, p_string);
                  
            x_coords.push_back(x_string.atoi());
            y_coords.push_back(y_string.atoi());
            timestamps.push_back(t_string.atoi());
            if (int'(p_string.atoi()) == 1) begin
                polarities.push_back(1'b1);
            end
            else begin
                polarities.push_back(1'b0);
            end

        end
        $fclose(file);

        // Get first values from queue
        timestamp_reg <= timestamps.pop_front();
        x_coord_reg   <= x_coords.pop_front();
        y_coord_reg   <= y_coords.pop_front();
        polarity_reg  <= polarities.pop_front();      

        while(1) begin
            if (cnt<10) begin
                rst <= 1'b1;
                cnt = cnt + 1;
            end
            else begin
                rst <= 1'b0;
            end
            #1 clk <= 1'b0;
            #1 clk <= 1'b1;
        end
    end
    always @(posedge clk) begin
        if (!rst) begin
            
            // Caluclate simulation time
            current_time_ns = current_time_ns + NS_PER_CLK;
            
            // Put values on input whenever the timestamp is smaller than simultation time
            if (timestamp_reg * 1000 < current_time_ns) begin
                is_valid <= 1;
                timestamp_reg <= timestamps.pop_front();
                x_coord_reg   <= x_coords.pop_front();
                y_coord_reg   <= y_coords.pop_front();
                polarity_reg  <= polarities.pop_front();                
            end
            else begin
                 is_valid <= 0;
            end

            mem_ptr_last <= mem_ptr;
            if (mem_ptr_last != mem_ptr) begin
                note_t <= note_t + 1;
            end

            timestamp <= timestamp_reg;
            x_coord <= x_coord_reg;
            y_coord <= y_coord_reg;
            polarity <= polarity_reg;

            // Write outputs to file
            if (valid && out_edges[4]) begin
                $fwrite(file_out, "[%0d, %0d, %0d][", node_x, node_y, note_t);
                for (int i = 31; i > 0; i=i-1) begin
                    $fwrite(file_out, "%0d, ", features[i]);
                end
                $fdisplay(file_out, "%0d]", features[0]);
            end

            // Finish simulation after 50.1 ms
            if (current_time_ns > 25000000) begin
                $fclose(file_out);
                $finish;
            end
        end
    end


    top #(
        .MAX_X_COORD ( MAX_X_COORD ),
        .MAX_Y_COORD ( MAX_Y_COORD )
    ) dut (
        .clk            ( clk         ),
        .reset          ( rst         ),
        .timestamp      ( timestamp   ),
        .x_coord        ( x_coord     ),
        .y_coord        ( y_coord     ),
        .polarity       ( polarity    ),
        .is_valid       ( is_valid    ),
        .out_addr_conv5     (out_addr),
        .features_conv5 (features),
        .out_edges_conv5 (out_edges),
        .out_valid_conv5 (valid),
        .mem_ptr_conv5(mem_ptr)
    );


endmodule
