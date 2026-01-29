//uart_tx_engine.sv
//it uses baud_x16_tick, each data bit lasts 16 ticks
//Handshake condition => tx_in_valid && tx_in_ready
//TX stream contract:
//-Upstream assert tx)in_valid with stable tx_in data
//-This TX engine assers tx_in ready only when it can accept a new byte (in the IDLE state)

module uart_tx_engine(
	input	logic		clk,
	input	logic		rst_n,
	
	input	logic		baud_x16_tick,
	
	//Streaming TX input (from FIFO adapter or MMIO)
	input		logic			tx_in_valid,
	output	logic			tx_in_ready,
	input		logic	[7:0]	tx_in_data,
	
	//UART TX pin
	output	logic	uart_tx,
	
	//Status
	output	logic	tx_busy);
	
	
	typedef enum logic	[1:0]
	{
		S_IDLE	=	2'd0,
		S_START	=	2'd1,
		S_DATA	=	2'd2,
		S_STOP	=	2'd3
	} state_t;
	
	state_t	current_state, state_next;
	
	//0-15	(16 ticks per bit)
	logic [3:0] tick_counter;			
	logic	[3:0]	tick_counter_next;
	
	//0-7		(shift register is 8 bit long)
	logic	[2:0]	bit_idx;					
	logic	[2:0]	bit_idx_next;
	
	// shift register (LSb-first)
	logic	[7:0] shift_reg;				
	logic	[7:0]	shift_reg_next;
	
	//fire signals (similar to flags)
	logic	tx_fire;		//stream transfer event (accept new byte) 
	logic	bit_fire;	//bit_boundary event	(advance UART bit)
	logic x16_fire;	//alias for the tick; readibility and we want to add more signals
	
	//Handshake / status
	assign tx_in_ready	= (current_state == S_IDLE);
	assign tx_busy			= (current_state != S_IDLE);	
	
	//fire signal assigment (flags)
	assign	tx_fire	=	tx_in_valid	&&	tx_in_ready; //both producer and consumer are ready
	assign	bit_fire	=	baud_x16_tick && (tick_counter == 4'd15);
	assign	x16_fire	=	baud_x16_tick;
	
	//UART TX output (Moore-style)
	always_comb
	begin
		unique case (current_state)
			S_IDLE:	uart_tx	=	1'b1;
			S_START:	uart_tx	=	1'b0;
			S_DATA:	uart_tx	=	shift_reg[0];
			S_STOP:	uart_tx	=	1'b1;
			default:	uart_tx	=	1'b1;
		endcase
	end
	
	
	//logic for next state
	always_comb
	begin
		state_next = current_state; //default: hold whatever the state register is holding
		unique case (current_state)
			S_IDLE:	if(tx_fire)									state_next	=	S_START;
			S_START:	if(bit_fire)								state_next	=	S_DATA;
			S_DATA:	if(bit_fire	&& (bit_idx == 3'd7))	state_next	=	S_STOP;
			S_STOP:	if(bit_fire)								state_next	=	S_IDLE;
			default:													state_next	=	S_IDLE;
		endcase	
	end
	
	//logic for subcounter (tick_counter)
	always_comb
	begin
		tick_counter_next	=	tick_counter;
		if(current_state == S_IDLE)
			tick_counter_next = 4'd0;
		else
		begin
			if(x16_fire)
				tick_counter_next	=	(tick_counter == 4'd15)	?	4'd0	:	(tick_counter	+	4'd1);
		end	
	end
	
	//bit index update
	always_comb
	begin
		bit_idx_next	=	bit_idx;
		if((current_state == S_IDLE) || (current_state == S_START) || (current_state == S_STOP) )
			bit_idx_next	=	3'd0;
		else if((current_state == S_DATA) && (bit_fire) && (bit_idx != 3'd7))
			bit_idx_next =	bit_idx + 3'd1;
	end

	//
	always_comb
	begin
		shift_reg_next = shift_reg;
		if(current_state == S_IDLE && tx_fire)
			shift_reg_next =	tx_in_data;
		else if(current_state == S_DATA && bit_fire)
			shift_reg_next	=	{1'b0, shift_reg[7:1]};
	end
	
	//Register stage for next-state style FSM
	//commits the *_next file into registers on rising edge
	//
	always_ff @(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
		begin
			current_state 	<= S_IDLE;
			tick_counter	<= 4'd0;
			bit_idx			<=	3'd0;
			shift_reg		<=	8'd0;
		end
		else
		begin
			current_state 	<= state_next;
			tick_counter	<= tick_counter_next;
			bit_idx			<=	bit_idx_next;
			shift_reg		<=	shift_reg_next;
		end
	end
	
endmodule