module	timer	#(
	parameter int unsigned CLOCK_HZ		=	50_000_000,
	parameter int unsigned LENGTH_S	=	0,
	parameter int unsigned LENGTH_MS	= 	0,
	parameter int unsigned LENGTH_US	=	0,
	parameter int unsigned LENGTH_NS	=	50)
	(
	input		logic clk,
	input		logic	reset_n,
	output	logic timer_done);
						
endmodule
