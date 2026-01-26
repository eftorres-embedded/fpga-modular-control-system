//uart_rx_engine.sv

module uart_rx_engine(
	input		logic			clk,
	input		logic			rst_n,
	
	input		logic			baud_x16_tick,		//1-cycle pulse at 16x baud rate
	input		logic			uart_rx,				//async pin, iddle high
	
	//RX output (interface to FIFO adapter or MMIO)
	output	logic			rx_out_valid,
	input		logic			rx_out_ready,
	output	logic	[7:0]	rx_out_data,
	
	//status bit
	output	logic			rx_busy);
	
	
	//Synchronizer for rx signal (since it's asynchrounous)
	//to avoid metastability
	logic uart_rx_ff1, uart_rx_ff2;
	logic uart_rx_sync;
	always_ff	@(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
		begin
			uart_rx_ff1	<=	1'b1;
			uart_rx_ff2	<= 1'b1;
		end
		else
		begin
			uart_rx_ff1		<=	uart_rx;
			uart_rx_ff2		<=	uart_rx_ff1;
		end
	end
	
	assign uart_rx_sync = uart_rx_ff2;
	
	
	typedef enum logic	[2:0]
	{
		S_IDLE	=	3'd0,
		S_START	=	3'd1,
		S_DATA	=	3'd2,
		S_STOP	=	3'd3,
		S_HOLD	=	3'd4	//holding a received byte until rx_out_ready
	} state_t;

	state_t	current_state,	state_next;
	
	//tick counter (16 bits per bit)
	logic	[3:0]	tick_counter, tick_counter_next; //count ticks, 0-15 (16 ticks per bit)
	
	//bit index (8 data bits)
	logic	[2:0] bit_index, bit_index_next;
	
	//shift register for received byte (LSB-first)
	logic [7:0] shift_reg, shift_reg_next;
	
	//output buffer register (holds byte while rx_out_valid=1)
	logic	[7:0] output_buffer, output_buffer_next;
	logic			output_valid, output_valid_next;
	
	////////////fire signals/////////////////////
	logic x16_fire;		//alias for baud_x16_tick
	logic	sample_fire;	//center-sample event within a bit
	logic	bit_end_fire;	//end-of-bit event (tick_counter==15)
	logic	rx_fire;			//output stream transfer
	
	//alias for baud_x16_tick input
	assign x16_fire	=	baud_x16_tick;
	
	//output_valid is an alias for rx_out_valid
	assign rx_out_valid	=	output_valid;
	
	//condition to sample, sample on incoming tick and on half the tick counter reg
	assign sample_fire	=	x16_fire && (tick_counter	== 4'd7); 
	
	//shows that the current bit should be done
	assign bit_end_fire	=	x16_fire	&& (tick_counter	==	4'd15);
	
	//Stream handshake event: downstream consumes the buffered RX byte
	assign rx_fire = output_valid && rx_out_ready;
	
	
	/////////Outputs/////////////////////////////////////
	
	assign rx_out_data	=	output_buffer;
	assign rx_busy			=	(current_state !=	S_IDLE);
	
	
	///////////////////////////////////////////////////////
	////////////// Control: next-state logic///////////////
	///////////////////////////////////////////////////////
	always_comb
	begin
		state_next	= current_state;
		unique	case	(current_state)
			//Wait for the start bit (when the rx line goes low)
			S_IDLE:
			begin
				if(output_valid)
					state_next	= S_HOLD;
				else if(uart_rx_sync == 1'b0)
					state_next = S_START;
			end
			
			//At the 7th tick, it checks if the signal still low and not a glitch has occured
			S_START:
			begin
				if(sample_fire) //tick_counter == 7 and on that tick. 
				begin
					if(uart_rx_sync	==	1'b0)
						state_next	= 	S_DATA;
					else
						state_next	=	S_IDLE;
				end
			end
			
			S_DATA:
			begin
				//After 8 bits, move to the stop bit.
				if((bit_index	==	3'd7) && bit_end_fire) //if at the 7th bit and the 7th bit ends
					state_next	=	S_STOP;
			end
			
			S_STOP:
			begin
				//Wait for the stop-bit to finish being transmitted
				if(bit_end_fire)
					state_next	=	S_HOLD;
			end
			
			S_HOLD:
			begin
				//Hold byte until downstream accepts it
				if(rx_fire)
					state_next	=	S_IDLE; //both valid and ready are true
			end
			
			default: state_next	=	 S_IDLE;
		endcase
	end
	
	/////////////////////////////////////////
	//////////Datapath: tick counter/////////
	/////////////////////////////////////////
	always_comb
	begin
		tick_counter_next	=	tick_counter;
		
		if(current_state	==	S_IDLE)
			tick_counter_next	=	4'd0;
		else if	(x16_fire)
			tick_counter_next	=	(tick_counter ==	4'd15)	?	4'd0	:	(tick_counter	+ 4'd1);
	end

	//////////////////////////////////////////
	/////Datapath: bit index//////////////////
	//////////////////////////////////////////
	always_comb
	begin
		bit_index_next	=	bit_index;
		
		if(current_state != S_DATA)
			bit_index_next	=	3'd0;
		else
			//Advance bit index at the  of each data-bit cell
			if(bit_end_fire && (bit_index	!=	3'd7))
				bit_index_next	=	bit_index	+	3'd1;
	end
	
	///////////////////////////////////////////
	/////Datapath: shift register capture//////
	///////////////////////////////////////////
	always_comb
	begin
		shift_reg_next	=	shift_reg;
		
		if(current_state	==	S_IDLE)
			shift_reg_next	=	8'd0;
		else if(current_state	==	S_DATA)
		begin
			//Center-sample each data bit (LSB-First)
			if(sample_fire)
			begin
				shift_reg_next[bit_index]	=	uart_rx_sync;
			end
		end
	end
	
	///////////////////////////////////////////
	///////Datapath: output buffer ////////////
	///////////////////////////////////////////
	always_comb
	begin
		output_buffer_next	=	output_buffer;
			
		//Commit received byte at end of STOP state
		if((current_state	==	S_STOP)	&&	bit_end_fire)
		begin
			output_buffer_next	=	shift_reg;
		end			
	end
	
	///////////////////////////////////////////
	/////////Datapath: valid///////////////////
	///////////////////////////////////////////
	always_comb
	begin
		output_valid_next	=	output_valid;
		
		//Clears valid when downstream consumes
		if(rx_fire)
			output_valid_next	=	1'b0;
		else if((current_state	==	S_STOP)	&&	bit_end_fire)
			output_valid_next	=	1'b1;
	end
	
	///////////////////////////////////////////
	//////////////Registers////////////////////
	///////////////////////////////////////////
	always_ff	@(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
		begin
			current_state	<=	S_IDLE;
			tick_counter	<=	4'd0;
			bit_index		<=	3'd0;
			shift_reg		<=	8'd0;
			output_buffer	<=	8'd0;
			output_valid	<=	1'b0;
		end
		
		else
		begin
			current_state	<=	state_next;
			tick_counter	<=	tick_counter_next;
			bit_index		<=	bit_index_next;
			shift_reg		<=	shift_reg_next;
			output_buffer	<=	output_buffer_next;
			output_valid	<=	output_valid_next;
		end
	end
endmodule