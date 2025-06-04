`timescale 1ns / 1ps

module example__gen_graph_ut;

    parameter MAX_X_COORD = 240;
    parameter MAX_Y_COORD = 180;
    parameter OUTPUT_PATH = "/home/pwzorek/Repo/Event2Graph/result/example_gen_graph.txt";
    parameter NS_PER_CLK = 5; // 250MHz is 4 clk every ns
    parameter TIME_WINDOW = 100000; // We test only single time window

    logic clk;
    logic rst;
    graph_pkg::event_type pos_item;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] edges;

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
        file_out = $fopen(OUTPUT_PATH, "w");

        // Save timestamps GIT
        timestamps.push_back(10);
        polarities.push_back(1);       
        x_coords.push_back(10);
        y_coords.push_back(10);
        
        //[0 +1 -1] edge GIT
        timestamps.push_back(50); 
        polarities.push_back(0);
        x_coords.push_back(11);
        y_coords.push_back(9);       
        
        //event to drop
        timestamps.push_back(60);
        polarities.push_back(1);
        x_coords.push_back(11);
        y_coords.push_back(9);       

        //Multiple edges
        timestamps.push_back(250);
        polarities.push_back(0);
        x_coords.push_back(9);
        y_coords.push_back(11);

        //Event with edge in the same coordinate
        timestamps.push_back(260);
        polarities.push_back(1);
        x_coords.push_back(10);
        y_coords.push_back(10);       
        
        // Time distance condition check  
        timestamps.push_back(600);
        polarities.push_back(0);
        x_coords.push_back(9);
        y_coords.push_back(10);
        
        // Event close to the border
        timestamps.push_back(800);
        polarities.push_back(1);
        x_coords.push_back(0);
        y_coords.push_back(0);
        
        // Edge close in time
        timestamps.push_back(801);
        polarities.push_back(0);
        x_coords.push_back(1);
        y_coords.push_back(1);

        // Event in last deltaT
        timestamps.push_back(99900);
        polarities.push_back(0);
        x_coords.push_back(1);
        y_coords.push_back(1);

        // Event in first delta T
        timestamps.push_back(100050);
        polarities.push_back(0);
        x_coords.push_back(120);
        y_coords.push_back(120);

        // Event in first delta T [POŁĄCZ]
        timestamps.push_back(100100);
        polarities.push_back(0);
        x_coords.push_back(2);
        y_coords.push_back(1);

        // Get first values from queue
        timestamp_reg = timestamps.pop_front();
        x_coord_reg   = x_coords.pop_front();
        y_coord_reg   = y_coords.pop_front();
        polarity_reg  = polarities.pop_front();

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

            timestamp <= timestamp_reg;
            x_coord <= x_coord_reg;
            y_coord <= y_coord_reg;
            polarity <= polarity_reg;

            // Write outputs to file
            if (pos_item.valid) begin
                $fdisplay(file_out, "POS = %0d %0d %0d %0d", pos_item.t, pos_item.x, pos_item.y, pos_item.p);
                for (int i = 0; i < graph_pkg::MAX_EDGES; i=i+1) begin
                    if (edges[i].is_connected) begin
                        $fdisplay(file_out, "EDGE_%0d = %0d %0d %0d", i, edges[i].is_connected, edges[i].t, edges[i].attribute);
                    end
                end
            end

            // Finish simulation after 50.1 ms
            if (current_time_ns > 100500000) begin
                $fclose(file_out);
                $finish;
            end
        end
    end


    generate_graph #(
        .MAX_X_COORD ( 256 ),
        .MAX_Y_COORD ( 256 )
    ) dut (
        .clk            ( clk         ),
        .reset          ( rst         ),
        .timestamp      ( timestamp   ),
        .x_coord        ( x_coord     ),
        .y_coord        ( y_coord     ),
        .polarity       ( polarity    ),
        .is_valid       ( is_valid    ),
        .pos_item       ( pos_item    ),
        .edges          ( edges       )
    );


endmodule
