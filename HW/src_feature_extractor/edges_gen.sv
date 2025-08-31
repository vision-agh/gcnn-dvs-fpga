`timescale 1ns / 1ps

module edges_gen #(
    parameter int GRAPH_SIZE     = graph_pkg::GRAPH_SIZE,
    parameter int RADIUS         = graph_pkg::RADIUS,
    parameter int COUNTER_WIDTH  = 9,
    parameter int TIME_WINDOW    = graph_pkg::TIME_WINDOW
)( 
    input  logic                                             clk,
    input  logic                                             reset,
    input  graph_pkg::event_type                             in_event,
    input  logic [COUNTER_WIDTH-1 : 0]                       window_counter,
    output graph_pkg::event_type                             out_event,
    output graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] edges
);
    localparam GRAPH_WIDTH    = $clog2(GRAPH_SIZE); // The GRAPH values width in bits
    localparam MEMORY_OPS_NUM = graph_pkg::MEMORY_OPS_NUM;

    localparam logic [1:0] MEM_ADDR_A_X [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_ADDR_A_X;
    localparam bit         MEM_SIGN_A_X [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_SIGN_A_X;

    localparam logic [1:0] MEM_ADDR_B_X [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_ADDR_B_X;
    localparam bit         MEM_SIGN_B_X [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_SIGN_B_X;

    localparam logic [1:0] MEM_ADDR_B_Y [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_ADDR_B_Y;
    localparam logic [1:0] MEM_ADDR_A_Y [MEMORY_OPS_NUM-1:0] = graph_pkg::MEM_ADDR_A_Y;

    ///////////////////////////////////////////////////////////
    //                       INPUT FIFO                      //
    // Store normalized events in case of high dynamic scene //
    ///////////////////////////////////////////////////////////
    
    logic                                     fifo_empty;
    logic                                     fifo_full;
    logic                                     fifo_read;
    logic                                     fifo_write;
    logic [$clog2(MEMORY_OPS_NUM)-1 : 0]      counter;
    logic [$clog2(GRAPH_SIZE*GRAPH_SIZE) : 0] counter_reset;
    logic [$clog2(MEMORY_OPS_NUM)-1 : 0]      counter_reg;
    logic [3*GRAPH_WIDTH+COUNTER_WIDTH:0]     fifo_in;
    logic [3*GRAPH_WIDTH+COUNTER_WIDTH:0]     fifo_out;
    graph_pkg::event_type                     fifo_event;
    logic [COUNTER_WIDTH-1 : 0]               fifo_window_counter;
    
    logic ena;
    logic wea;
    logic web;
    logic enb;
    
    always @(posedge clk) begin
        if (reset) begin
            fifo_write <= 0;
            counter_reset <= '0;
        end
        else begin
            fifo_write <= 0;
            fifo_in <= {window_counter, in_event.t, in_event.x, in_event.y, in_event.p};
            if (in_event.valid) begin
                fifo_write <= 1;
            end
        end
    end

    assign fifo_read = !fifo_empty && counter == MEMORY_OPS_NUM-1;
    
    fifo_generator_0 fifo_0 (
        .clk   ( clk        ),
        .din   ( fifo_in    ),
        .wr_en ( fifo_write ),
        .rd_en ( fifo_read  ),
        .dout  ( fifo_out   ),
        .full  ( fifo_full  ),
        .empty ( fifo_empty )
    );
    
    // synthesis translate_off
    always @(posedge in_event.valid) begin
        if (fifo_full) begin
            $display("FIFO OVERFLOW - EXIT THE SIMULATION");
            $stop;
        end
    end
    // synthesis translate_on

    assign fifo_window_counter = fifo_out[3*GRAPH_WIDTH+COUNTER_WIDTH : 3*GRAPH_WIDTH+1];
    assign fifo_event.t = fifo_out[3*GRAPH_WIDTH : (2*GRAPH_WIDTH)+1];
    assign fifo_event.x = fifo_out[2*GRAPH_WIDTH : GRAPH_WIDTH+1];
    assign fifo_event.y = fifo_out[GRAPH_WIDTH   : 1 ];
    assign fifo_event.p = fifo_out[0];

    ////////////////////////////////////////////////////////////
    //                    UPDATE CONTEXT                      //
    // Read from context and update it, drop duplicate events //
    ////////////////////////////////////////////////////////////

    localparam ADDR_WIDTH = $clog2(GRAPH_SIZE*GRAPH_SIZE);
    localparam DATA_WIDTH = GRAPH_WIDTH+2+COUNTER_WIDTH; //Timestapm, polarity and is_empty

    logic [ADDR_WIDTH-1:0] addra;
    logic [ADDR_WIDTH-1:0] addrb;
    logic [DATA_WIDTH-1:0] dina;
    logic [DATA_WIDTH-1:0] douta;
    logic [DATA_WIDTH-1:0] doutb;


    // Context memroy module
    memory #(
        .AWIDTH   ( ADDR_WIDTH ),
        .DWIDTH   ( DATA_WIDTH ),
        .RAM_TYPE ( "block"    )
    ) gen_memory  (
        .clk      ( clk   ),
        .mem_ena  ( ena   ),
        .wea      ( wea   ),
        .addra    ( addra ),
        .dina     ( dina  ),
        .dinb     ( '0    ),
        .douta    ( douta ),
        .mem_enb  ( enb   ),
        .web      ( web   ),
        .addrb    ( addrb ),
        .doutb    ( doutb )
    );

    // Memory control logic
    logic rd_a;
    logic wr_a;
    logic rd_a_reg;
    logic rd_b_reg;
    logic condition_a;
    logic condition_b;
    logic [GRAPH_WIDTH-1:0] x_coord_a;
    logic [GRAPH_WIDTH-1:0] x_coord_b;
    graph_pkg::edge_type [graph_pkg::MAX_EDGES-1 : 0] edges_reg;

    assign rd_a = ena & !wea;
    assign wr_a = ena & wea;

    assign ena = (counter <= MEMORY_OPS_NUM-1 & condition_a) ? 1 : 0;
    assign enb = (counter <= MEMORY_OPS_NUM-1 & condition_b) ? 1 : 0;
    assign wea = (counter == MEMORY_OPS_NUM-1) ? 1 : 0;
    assign web = 0;

    assign x_coord_a = (MEM_SIGN_A_X[counter] > 0) ? (fifo_event.x - MEM_ADDR_A_X[counter]) : (fifo_event.x + MEM_ADDR_A_X[counter]);
    assign x_coord_b = (MEM_SIGN_B_X[counter] > 0) ? (fifo_event.x - MEM_ADDR_B_X[counter]) : (fifo_event.x + MEM_ADDR_B_X[counter]);

    assign condition_a = (GRAPH_SIZE > x_coord_a + fifo_event.x >= 0) & 
                         (GRAPH_SIZE > (fifo_event.y - MEM_ADDR_A_Y[counter]) >= 0);
    assign condition_b = (GRAPH_SIZE > (fifo_event.y + MEM_ADDR_B_Y[counter]) >= 0) &
                         (GRAPH_SIZE > x_coord_b + fifo_event.x >= 0);

    // ADDR = Y*GRAPH SIZE + X
    assign addra = (fifo_event.y - MEM_ADDR_A_Y[counter]) * GRAPH_SIZE + x_coord_a;
    assign addrb = (fifo_event.y + MEM_ADDR_B_Y[counter]) * GRAPH_SIZE + x_coord_b;
    assign dina  = {fifo_window_counter, fifo_event.t, fifo_event.p, 1'b1};


    logic [$clog2(RADIUS) : 0] diff_t_a;
    logic                      condition_a_1, condition_a_2, connect_a;
    assign diff_t_a = fifo_event.t >= douta[GRAPH_WIDTH+1:2] ? fifo_event.t-douta[GRAPH_WIDTH+1:2] : (fifo_event.t+128)-douta[GRAPH_WIDTH+1:2];
    assign condition_a_1 = ((fifo_event.t-douta[GRAPH_WIDTH+1:2]) <= RADIUS) && 
                           fifo_window_counter == douta[DATA_WIDTH-1:GRAPH_WIDTH+2] && 
                           (fifo_event.t >= douta[GRAPH_WIDTH+1:2]);
    assign condition_a_2 = fifo_event.t < RADIUS && 
                           (douta[GRAPH_WIDTH+1:2] - fifo_event.t) >= (GRAPH_SIZE-RADIUS) &&
                           fifo_window_counter == douta[DATA_WIDTH-1:GRAPH_WIDTH+2]+1;
    assign connect_a = condition_a_1 || condition_a_2;

    logic [$clog2(RADIUS) : 0] diff_t_b;
    logic                      condition_b_1, condition_b_2, connect_b;
    logic                  fake_event;
    assign fake_event = (fifo_event.x == 0) && (fifo_event.y == 0) && (fifo_event.p == 0);
    assign diff_t_b = fifo_event.t >= doutb[GRAPH_WIDTH+1:2] ? fifo_event.t-doutb[GRAPH_WIDTH+1:2] : (fifo_event.t+128)-doutb[GRAPH_WIDTH+1:2];
    assign condition_b_1 = ((fifo_event.t-doutb[GRAPH_WIDTH+1:2]) <= RADIUS) && 
                           fifo_window_counter == doutb[DATA_WIDTH-1:GRAPH_WIDTH+2] && 
                           (fifo_event.t >= doutb[GRAPH_WIDTH+1:2]) && !fake_event;
    assign condition_b_2 = fifo_event.t < RADIUS && 
                           (doutb[GRAPH_WIDTH+1:2] - fifo_event.t) >= (GRAPH_SIZE-RADIUS) &&
                           fifo_window_counter == doutb[DATA_WIDTH-1:GRAPH_WIDTH+2]+1;
    assign connect_b = condition_b_1 || condition_b_2;

    always @(posedge clk) begin
        if (reset) begin
            rd_a_reg <= 0;
            rd_b_reg <= 0;
            counter_reg <= 0;
            counter <= MEMORY_OPS_NUM-1;
        end
        else begin
            rd_a_reg <= rd_a;
            rd_b_reg <= enb;
            counter_reg <= counter;
            if (counter < MEMORY_OPS_NUM-1) begin
                counter <= counter + 1;
            end
            else begin
                counter <= 0;

            end
        
            // Port A (14 reads and write)
            if (counter_reg != MEMORY_OPS_NUM-1) begin
                edges_reg[counter_reg].t <= (rd_a_reg & douta[0]) ? diff_t_a : '0;
                edges_reg[counter_reg].attribute <= (rd_a_reg & douta[0]) ? douta[1] : '0;
                edges_reg[counter_reg].is_connected <= (rd_a_reg & douta[0]) & connect_a;
            end

            // Port B (15 reads)
            edges_reg[MEMORY_OPS_NUM-1+counter_reg].t <= (rd_b_reg & doutb[0]) ? diff_t_b : '0;
            edges_reg[MEMORY_OPS_NUM-1+counter_reg].attribute <= (rd_b_reg & doutb[0]) ? doutb[1] : '0;
            edges_reg[MEMORY_OPS_NUM-1+counter_reg].is_connected <= (rd_b_reg & doutb[0]) & connect_b;
        end
    end
    
    ///////////////////////////////////////////////////////////////
    //                         DELAY EVENT                       //
    // Delay event form FIFO to output to synchronize with edges //
    ///////////////////////////////////////////////////////////////

    logic valid_d1;
    logic valid_d2;
    logic valid_d3;
   
    delay_module #(
        .N       ( 1 ),
        .DELAY   ( 3 )
    ) delay_valid_1  (
        .clk   ( clk       ),
        .idata ( fifo_read ),
        .odata ( valid_d1  )
    );

    assign valid_d2 = valid_d1;
    //assign valid_d2 = valid_d1;
    
    delay_module #(
        .N        ( 1  ),
        .DELAY    ( 12 )
    ) delay_valid_2 (
        .clk   ( clk      ),
        .idata ( valid_d2 ),
        .odata ( valid_d3 )
    );
    
    ///////////////////////////////////////////////////////
    //                  CHECK CONDITION                  //
    // Check neighbourhood condition and generate edges  //
    ///////////////////////////////////////////////////////

    graph_pkg::event_type h1_event;
    graph_pkg::event_type reg_event;

    // Control output event
    always @(posedge clk) begin
        h1_event <= fifo_event;
        h1_event.valid <= valid_d3;
        reg_event <= h1_event;
        out_event <= reg_event;
    end
    
    genvar i, j;
    generate
        for (i=0; i<MEMORY_OPS_NUM-1; i++) begin: FIRST_13
            always @(posedge clk) begin
                edges[i].attribute <= edges_reg[i].attribute;
                edges[i].t <= edges_reg[i].t;
                edges[i].is_connected <= edges_reg[i].is_connected ? (((MEM_ADDR_A_X[i]**2) +
                                                                       (MEM_ADDR_A_Y[i]**2) +
                                                                      ((edges_reg[i].t)**2)) <= (RADIUS**2)) : '0;
            end
        end
        for (j=MEMORY_OPS_NUM-1; j<graph_pkg::MAX_EDGES; j++) begin: SECOND_14
            always @(posedge clk) begin
                edges[j].attribute <= edges_reg[j].attribute;
                edges[j].t <= edges_reg[j].t;
                edges[j].is_connected <= edges_reg[j].is_connected ? (((MEM_ADDR_B_X[j-(MEMORY_OPS_NUM-1)]**2) +
                                                                       (MEM_ADDR_B_Y[j-(MEMORY_OPS_NUM-1)]**2) +
                                                                       ((edges_reg[j].t)**2)) <= (RADIUS**2)) : '0;
            end
        end
    endgenerate

endmodule
