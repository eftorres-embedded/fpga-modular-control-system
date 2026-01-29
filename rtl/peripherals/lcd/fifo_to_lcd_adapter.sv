module fifo_to_lcd_adapter(
	input logic	clk,
	input logic	rst_n,
	
	//FIFO read side
	input 	logic			fifo_empty,
	input 	logic	[8:0] fifo_dout,
	output	logic			fifo_rd_en,
	
	//LCD host side
	input		logic			init_done,
	input		logic			host_ready,
	output	logic			host_valid,
	output	logic			host_rs,
	output	logic	[7:0]	host_data);
	
	typedef enum	logic	[1:0]
	{
		S_WAIT	=	2'd0,
		S_POP		=	2'd1,
		S_PULSE	=	2'd2
	}state_t;
	
	state_t current_state, state_next;
	

	//next state logic
	always_comb
	begin
		state_next	=	current_state; //default values
		
		unique case(current_state)
			S_WAIT:
			begin
				if(init_done && host_ready	&& !fifo_empty)
					state_next	=	S_POP;
			end
			
			S_POP:
			begin
				state_next	=	S_PULSE;
			end
			
			S_PULSE:
			begin
				state_next	=	S_WAIT;
			end
			
			default:	state_next	=	S_WAIT;
		endcase
	end
	
	//State register
	always_ff	@(posedge clk	or	negedge	rst_n)
	begin
		if(!rst_n)
			current_state	<=	S_WAIT;
		else
			current_state	<=	state_next;
	end
	
	
	//FSM output (moore)
	always_comb
	begin
		//defaults
		fifo_rd_en	=	1'b0;
		host_valid	=	1'b0;
		host_rs		=	fifo_dout[8];
		host_data	=	fifo_dout[7:0];
		
		unique case (current_state)
			S_POP:	fifo_rd_en	=	1'b1;		//1-cycle pop
			S_PULSE:	host_valid	= 1'b1;	//1-cycle valid pulse
			default:	/*keeps defaults*/;
		endcase
	end
	
endmodule	