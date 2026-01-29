module uart_port	#(
	parameter int unsigned DIV_WIDTH				=	9,
	parameter int unsigned CLK_HZ					=	50_000_000,
	parameter int unsigned DEFAULT_BAUDRATE	=	9_600,
	parameter int unsigned RX_FIFO_DEPTH		=	64)
	
	(
	input	logic				clk,
	input	logic				rst_n,
	
	//serial pins
	input		logic			uart_rx,
	output	logic			uart_tx,
	
	//x16 divider input to modify baudrate in runtime (by mcu)
	input		logic	[DIV_WIDTH-1:0]	div_x16,
	input		logic			baud_en,
	
	//tx upstream (no FIFO)
	input		logic			tx_valid,
	output	logic			tx_ready,
	input		logic	[7:0]	tx_data,
	output	logic			tx_busy, 
	
	//rx downstream stream (from RX FIFO output)
	output	logic			rx_valid,
	input		logic			rx_ready,
	output	logic	[7:0]	rx_data,
	
	//status
	output	logic			rx_busy, 
	output	logic			rx_fifo_full, 
	output	logic			rx_fifo_empty);
	
	
	/////////////////////////////////////////
	//Uart baud generator
	/////////////////////////////////////////
	logic baud_x16_tick;
	logic	baud_1x_tick;
	
	uart_baudgen #(
		.DIV_WIDTH(DIV_WIDTH),//slowest baud requires div_x16 to be 326
		.CLK_HZ(CLK_HZ),
		.DEFAULT_BAUDRATE(DEFAULT_BAUDRATE))
		
	u_uart_baudgen(
		.clk(clk),
		.rst_n(rst_n),
		.en(baud_en),		//enable tick generation
		
		//Runtime override baudrate: set to 0 to use default baudrate
		.div_x16(div_x16),
		
		.baud_x16_tick(baud_x16_tick),
		.baud_1x_tick(baud_1x_tick));
	
	/////////////////////////////////////////////
	//////////TX engine (no FIFO)////////////////
	/////////////////////////////////////////////
	uart_tx_engine u_uart_tx_engine(
		.clk(clk),
		.rst_n(rst_n),
		.baud_x16_tick(baud_x16_tick),

		.tx_in_valid(tx_valid),
		.tx_in_ready(tx_ready),
		.tx_in_data(tx_data),

		.uart_tx(uart_tx),
		.tx_busy(tx_busy));
	
	//////////////////////////////////////////////
	///////RX engine -> RX FIFO (write side)//////
	//////////////////////////////////////////////
	logic			rx_engine_valid;
	logic			rx_engine_ready;
	logic	[7:0]	rx_engine_data;
	
	uart_rx_engine	u_uart_rx(
		.clk(clk),
		.rst_n(rst_n),
		
		.baud_x16_tick(baud_x16_tick),	//1-cycle pulse at 16x baud rate
		.uart_rx(uart_rx),					//async pin, iddle high
		
		//RX output (interface to FIFO adapter or MMIO)
		.rx_out_valid(rx_engine_valid),
		.rx_out_ready(rx_engine_ready),
		.rx_out_data(rx_engine_data),
		
		//status bit
		.rx_busy(rx_busy));
	
	
	////////////////////////////////////////////////
	////RX FIFO  + stable output stage (bubble)/////
	////////////////////////////////////////////////
	
	//Fire signals to trigger events
	logic		rx_fifo_wr_fire;
	logic		rx_fifo_rd_en;
	logic		rx_fire;
	
	//registers to hold the data
	logic			out_valid,	out_valid_next;
	logic	[7:0]	out_data,	out_data_next;
	
	//signal will be valid one cycle after rd_en
	logic			fifo_dout_valid;
	
	//Internal FIFO signals
	logic	[7:0]	rx_fifo_dout;
	logic			rx_fifo_empty_int;

	//FIFO stores when RX	engine has a byte and FIFO is not full
	assign	rx_fifo_wr_fire	=	rx_engine_valid	&&	rx_engine_ready;
	
	//FIFO is ready to read as long as it's not full
	assign	rx_engine_ready	=	!rx_fifo_full;
	
	
	////////////////////////////////////////////////
	///////////RX FIFO instantiation////////////////
	////////////////////////////////////////////////
	sync_fifo	#(
		.DEPTH(RX_FIFO_DEPTH),
		.WIDTH(8))
		
	u_rx_fifo(
		.clk		(clk),
		.rst_n	(rst_n),
		
		//write side
		.wr_en	(rx_fifo_wr_fire),
		.din		(rx_engine_data),
		.full		(rx_fifo_full),
		
		//read side
		.rd_en	(rx_fifo_rd_en),
		.dout		(rx_fifo_dout),
		.empty	(rx_fifo_empty_int), //internal signal: FIFO storage only
		
		.count());//how many items in the fifo
		
	/////////////////////////////////////////////
	///////Adding delay on out_valid/////////////
	///////because fifo has a registered/////////
	///////output////////////////////////////////
	/////////////////////////////////////////////
		
	//Exposed RX stream interface
	assign	rx_valid			=	out_valid;
	assign	rx_data			=	out_data;
	
	//Stream transfer event: downstream consumes one byte this cycle
	assign	rx_fire				=	rx_valid	&&	rx_ready;
	
	//read the FIFO (pop), only if the buffer has not valid data and
	//if it's not empty. If out_valid == 1, then buffer is full.
	//Also, if rx_fire (output is being consumed this cycle, also pop from FIFO
	assign 	rx_fifo_rd_en	=	(!out_valid || rx_fire)	&&	(!rx_fifo_empty_int);
	//external empty status: no byte available to downstream
	assign	rx_fifo_empty	=	rx_fifo_empty_int && !out_valid; 
	
	//Set FIFO dout valid
	always_ff	@(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
			fifo_dout_valid 	<=	1'b0;
		else
			fifo_dout_valid	<=	rx_fifo_rd_en; //rx_fifo_rd_en
	end
	
	
	
	//Next-state logic for out_valid
	always_comb
	begin
		out_valid_next	=	out_valid;
	//consume buffered byte: if rx_fire and fifo_dout_valid are both 1 
	//in the same cycle, we refill immediately (out_valid_next ends high)
		if(rx_fire)
			out_valid_next	=	1'b0;
		if(fifo_dout_valid)
			out_valid_next	=	1'b1;
	end
	
	always_ff @(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
			out_valid	<=	1'b0;
		else
			out_valid	<=	out_valid_next;
	end
	
	
	
	//Next-state logic for out_data_next;
	always_comb
	begin
		out_data_next	=	out_data;
		//Refill from FIFO (dout is valid this cycle)
		if(fifo_dout_valid)
			out_data_next	=	rx_fifo_dout;
	end
	
	always_ff @(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
			out_data	<=	8'd0;
		else
			out_data	<=	out_data_next;
	end
	
	endmodule
	