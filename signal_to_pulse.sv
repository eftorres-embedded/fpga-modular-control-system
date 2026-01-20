module signal_to_pulse(
								input 	logic clock, 
								input		logic	signal, 
								output	logic	pulse);
								

								
typedef enum logic [1:0]
{
	STATE1,
	STATE2,
	STATE3
} state_t;

state_t current_state, next_state;


logic sync1, sync2;



always_ff @(posedge clock)
begin
	sync1 <= signal;
end


always_ff @(posedge clock)
begin 
	sync2 <= sync1;
end



always_ff @(posedge clock)
begin
	current_state <= next_state;
end

//always_comb
//begin
//	case(current_state)
//		STATE1:	next_state = sync2 ? STATE2 : STATE1;
//		STATE2:	next_state = sync2 ? STATE3 : STATE1;
//		STATE3:	next_state = sync2 ? STATE3 : STATE1;
//		default: next_state = STATE1;
//	endcase
//end

always_comb
begin
	next_state = current_state;
	
	case(current_state)
		STATE1:
			if(sync2)
			begin
				next_state = STATE2;
			end
			else
			begin
				next_state = STATE1;
			end
		
		
		STATE2:
			if(sync2)
			begin
				next_state = STATE3;
			end
			else
			begin
				next_state = STATE1;
			end
				
		STATE3:
			if(sync2)
				begin
					next_state = STATE3;
				end
			else
				begin
					next_state = STATE1;
				end
				
		default: 
			next_state = STATE1;
			
			
	endcase
end

assign pulse = (current_state == STATE2);

endmodule
	