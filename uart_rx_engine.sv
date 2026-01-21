//uart_rx_engine.sv

module uart_rx_engine(
	input		logic			clk,
	input		logic			rst_n,
	
	input		logic			baud_x16_tick,		//1-cycle pulse at 16x baud rate
	input		logic			uart_rx,				//async pin, iddle high
	
	//RX output (interface to FIFO adapter or MMIO)
	output	logic			rx_out_valid,
	input		logic			rx_out_ready,
	output	logic	[7:0]	rx_out_data
	
	//status bit
	output	logic			rx_busy);
	
	typedef enum logic	[2:0]
	{
		S_IDLE	=	3'd0,
		S_START	=	3'd1,
		S_DATA	=	3'd2,
		S_STOP	=	3'd3,
		S_HOLD	=	3'd4	//holding a received byte until rx_out_ready
	} state_t;

	state_t	current_state,	state_next;
	
	logic	[3:0]	tick_counter, tick_counter_next; //count ticks, 0-15 (16 tickes per bit)
	
	






endmodule