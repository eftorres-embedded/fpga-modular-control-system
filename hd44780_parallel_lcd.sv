module hd44780_parallel_lcd		#(
	parameter int unsigned CLOCK_HZ = 50_000_000,

	//https://users.ece.utexas.edu/~valvano/Datasheets/LCD.pdf
	//not specific datasheet for 1602 display, using above link at 3.3V
	//Long delays: worst case: 2.16mS, fast case: 1.18mS (depends on lcd clock
	//Short delays: worst case: 53uS, fast case 29uS
	//I'll convert all times to uS or ns
	//PowerUp time will be to 50mS for robustness, other people suggest 40mS
	parameter int unsigned	POWERUP_MS			=	50,		// initial power up wait time 50ms
	parameter int unsigned	ADDRESS_SETUP_NS	=	60,	// RS/RW setup time before E rises
	parameter int unsigned	ADDRESS_HOLD_NS	=	20,	//	Rs/rw hold after E falls
	
	// minimum time before E falls for DATA Setup
	//(it will be set as E rises, which it will ensure this timing is met, this parameter
	//will go unused, just included for documentation purposes
	parameter int unsigned	DATA_SETUP_NS		=	200, // round up from 195ns
	parameter int unsigned	E_PULSE_NS			=	500, // round up from 450ns
	parameter int unsigned	SHORT_DELAY_US		=	50,  // 50uS
	parameter int unsigned	LONG_DELAY_MS		=	2 // 2mS
	)
	(
	input logic clk, rst_n,

	//Host transaction interface
	// host_rs=0 => command
	// host_rs=1 => data
	// host_valid
	input		logic			host_valid, 	//host has valid data
	input 	logic 		host_rs,
	input 	logic [7:0]	host_data, 		//input data or command from host
	output 	logic 		host_ready, 	//module finished transaction (ready to receive a new txn

	//LCD interface
	output	logic			lcd_rs,
	output	logic			lcd_rw,
	output	logic			lcd_e,
	output	logic	[7:0]	lcd_data_o,
	input		logic	[7:0]	lcd_data_i,
	output	logic			lcd_data_oe,
	output	logic			init_done);
											
	//these functions will not be used inside an always block or called in an assigned statement
	//they will only be used to find the value of parameters, specifically, calculate how many
	//clock cycles are required to meet the timings, depending on the CLOCK_HZ parameter. 
	
	//ceiling(ns*CLK_HZ / 1e9)
	function automatic int unsigned cycles_from_ns(input int unsigned ns); 
		longint unsigned numerator; //to be used in ((ns * CLK_HZ) + 999,999,999)/(1,000,000,000))
		begin
			numerator		= longint'(ns) * longint'(CLOCK_HZ) + (1000_000_000 - 1);
			cycles_from_ns = int'(numerator/1000_000_000);
			
			if(cycles_from_ns == 0)
				cycles_from_ns = 1;
		end											
	endfunction
	
	//celing((us * CLOCK_HZ)/ 1e6)
	function automatic int unsigned cycles_from_us(input int unsigned us);
		longint unsigned numerator;
		begin
			numerator		=	longint'(us) * longint'(CLOCK_HZ) + (1_000_000 -1);
			cycles_from_us	=	int'(numerator/1_000_000);
			
			if(cycles_from_us == 0)
				cycles_from_us = 1;
		end
	endfunction
	
		//celing((ms * CLOCK_HZ)/ 1e3)
	function automatic int unsigned cycles_from_ms(input int unsigned ms);
		longint unsigned numerator;
		begin
			numerator		=	longint'(ms) * longint'(CLOCK_HZ) + (1_000 -1);
			cycles_from_ms	=	int'(numerator/1_000);
			
			if(cycles_from_ms == 0)
				cycles_from_ms = 1;
		end
	endfunction
	
	//the local parameter hold how many cycles are need to meet the timing requirenments
	//the functions above are used to calculate the # of cycles 
	localparam int unsigned	POWERUP_CYC			=	cycles_from_ms(POWERUP_MS);
	localparam int unsigned	ADDRESS_SETUP_CYC	=	cycles_from_ns(ADDRESS_SETUP_NS);
	localparam int unsigned	ADDRESS_HOLD_CYC	=	cycles_from_ns(ADDRESS_HOLD_NS);
	localparam int unsigned	DATA_SETUP_CYC		=	cycles_from_ns(DATA_SETUP_NS); //unused
	localparam int unsigned	E_PULSE_CYC			=	cycles_from_ns(E_PULSE_NS);
	localparam int unsigned	SHORT_DELAY_CYC	=	cycles_from_us(SHORT_DELAY_US);
	localparam int unsigned	LONG_DELAY_CYC		=	cycles_from_ms(LONG_DELAY_MS);
	
	//create a transaction_type structure (txn_t) it holds the byte to be written
	//on the data bus (MSB) and then the register-select bit (RS), and the lsb if
	//the transaction will be a long transaction or not (is_long)
	typedef struct packed {
	logic [7:0] data;
	logic			rs;			//	0=cmd,	1=data
	logic			is_long;		//	use long waite after this step
	} txn_t;
	
	//small 5 entry rom, 10-bit Word length
	//all commands, only clear display is long
	localparam int unsigned INIT_LEN	=	5 + 16 ;
	localparam txn_t	INIT_ROM	[INIT_LEN] =
	'{
	'{data:8'h38, rs:1'b0, is_long:1'b0}, //function set: 8-bit, 2-line, 5x8
	'{data:8'h08, rs:1'b0, is_long:1'b0}, //display off
	'{data:8'h01, rs:1'b0, is_long:1'b1}, //clear display
	'{data:8'h06, rs:1'b0, is_long:1'b0}, //Entry mode set: Incrempet/Accompanies display shift
	'{data:8'h0F, rs:1'b0, is_long:1'b0}, //Display on (sursor on, blink on)
	'{data:8'h45, rs:1'b1, is_long:1'b0}, //'E'
	'{data:8'h64, rs:1'b1, is_long:1'b0}, //'d'
	'{data:8'h65, rs:1'b1, is_long:1'b0}, //'e'
	'{data:8'h72, rs:1'b1, is_long:1'b0}, //'r'
	'{data:8'h20, rs:1'b1, is_long:1'b0}, //' '
	'{data:8'h26, rs:1'b1, is_long:1'b0}, //'&'
	'{data:8'h20, rs:1'b1, is_long:1'b0}, //' '
	'{data:8'h4A, rs:1'b1, is_long:1'b0}, //'J'
	'{data:8'h75, rs:1'b1, is_long:1'b0}, //'u'
	'{data:8'h64, rs:1'b1, is_long:1'b0}, //'d'
	'{data:8'h79, rs:1'b1, is_long:1'b0}, //'y'
	'{data:8'h20, rs:1'b1, is_long:1'b0}, //' '
	'{data:8'h3C, rs:1'b1, is_long:1'b0}, //'<'
	'{data:8'h33, rs:1'b1, is_long:1'b0}, //'3'
	'{data:8'h20, rs:1'b1, is_long:1'b0}, //' '	
	'{data:8'h80, rs:1'b0, is_long:1'b0}  //set ddram address to 0 (start at the first position of line 1
	};
	
	//creating a FSM state enumarations  to provide a readable state names in RTL, etc
	typedef enum logic	[3:0]
	{
		S_POWERUP_WAIT	=	4'd0,
		S_INIT_LATCH	=	4'd1,	//registers next ROM entry, update init_index
		S_IDLE			=	4'd2,
		S_TXN_LATCH		=	4'd3,	//registers transactions from HOST
		S_BUS_SETUP		=	4'd4,
		S_E_HIGH			=	4'd5,
		S_E_LOW			=	4'd6,
		S_WAIT_SHORT	=	4'd7,
		S_WAIT_LONG		=	4'd8
	} state_t;
	
	state_t	current_state;
	state_t	state_next;
	
	//creating a down counter register 
	//using $clog2 in case the delay timings parameters change from the default
	//could be removed if checking the status bit is implemented
	logic [$clog2(LONG_DELAY_CYC + 2) - 1: 0] timer; // +2 to avoid zero values as parameter	
	logic timer_done;	
	
	//registered transactions
	txn_t txn_r;
	
	//index for the current init ROM entry
	logic [($clog2(INIT_LEN+1)-1):0] init_index;
	
	
	
	
	function automatic logic is_long_cmd(input logic rs, input logic [7:0] d);
		begin
			is_long_cmd = (rs == 1'b0) && (( d == 8'h01) || (d == 8'h02));
		end
	endfunction
			
			
	//task to load the timer with the appropriate number 
	//of cycles needed to meet timing requirements
	task automatic load_timer(input int unsigned cycles);
		begin
			if(cycles == 0)
				timer <= '0;
			else
				timer	<=	cycles[$bits(timer)-1:0] - 1; //counts down to 0 inclusive
		end
	endtask
	
	assign timer_done = (timer == '0);//when timer hits "zero", set the flag: timer_done
	
			
	//next state circuitry
	always_comb
	begin
		state_next	=	current_state;
		unique case (current_state)
			S_POWERUP_WAIT:
			begin
				if(timer_done)
					state_next	=	S_INIT_LATCH;
			end
			
			S_INIT_LATCH:
			begin
				state_next	=	S_BUS_SETUP;
			end
			
			S_IDLE:
			begin
				if(host_valid)
					state_next	=	S_TXN_LATCH;
			end
			
			S_TXN_LATCH:
			begin
				state_next	=	S_BUS_SETUP;
			end
			
			S_BUS_SETUP:
			begin
				if(timer_done)
					state_next	=	S_E_HIGH;
			end
			
			S_E_HIGH:
			begin
				if(timer_done)
					state_next	=	S_E_LOW;
			end
			
			S_E_LOW:
			begin
				if(timer_done)
				begin
					if(txn_r.is_long)
						state_next	=	S_WAIT_LONG;
					else
						state_next	=	S_WAIT_SHORT;
				end
			end
			
			S_WAIT_SHORT:
			begin
				if(timer_done)
					begin
						if(!init_done)
							state_next	=	S_INIT_LATCH;
						else
							state_next	=	S_IDLE;
					end
			end
			
			S_WAIT_LONG:
			begin
				if(timer_done)
				begin
					if(!init_done)
						state_next	=	S_INIT_LATCH;
					else
						state_next	=	S_IDLE;
				end
			end
			
			default: state_next	=	S_IDLE;
			
		endcase
	end
	
	//state register update
	always_ff	@(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
			current_state	<=	S_POWERUP_WAIT;
		else
			current_state <= state_next;
	end
	
	////////////////////////////////////////////
	//timer update
	////////////////////////////////////////////
	always_ff	@(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
			timer	<=	'0;
		else
		begin
		//default: decrement timer if not done (only if stating in same state)
			if(current_state == state_next)
				begin
					if(!timer_done)
						timer <= timer - 1'b1;
				end

		
			//Entering-state action: load timer in the ENTERING state
			unique case (state_next)
				S_POWERUP_WAIT:
					if(current_state != S_POWERUP_WAIT)
						load_timer(POWERUP_CYC);
					
				S_BUS_SETUP:
					if(current_state	!=	S_BUS_SETUP)
						load_timer(ADDRESS_SETUP_CYC);
				
				S_E_HIGH:
					if(current_state != S_E_HIGH)
						load_timer(E_PULSE_CYC);
				
				S_E_LOW:
					if(current_state != S_E_LOW)
						load_timer(ADDRESS_HOLD_CYC);
				
				S_WAIT_SHORT:
					if(current_state != S_WAIT_SHORT)
						load_timer(SHORT_DELAY_CYC);
				
				S_WAIT_LONG:
					if(current_state != S_WAIT_LONG)
						load_timer(LONG_DELAY_CYC);
				
				default: /*no operation*/;
			endcase
		end
	end
			
			
	//init index and init_done
	always_ff	@(posedge clk or negedge rst_n)
	begin
	
		if(!rst_n)
		begin
			init_index	<=	'0;
			init_done	<=	1'b0;
		end
		
		else
		begin
			if(current_state == S_WAIT_SHORT	||	current_state	==	S_WAIT_LONG)
			begin
				if(state_next == S_INIT_LATCH)
				begin
					if(init_index	==	INIT_LEN - 1)
					begin
						init_done	<=	1'b1;
					end
					
					else
					begin
						init_index <= init_index + 1'b1;
					end
				end
			end
		end
				
	end
	
	
	//output
	always_ff	@(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
		begin
			txn_r.rs			<=	1'b0;
			txn_r.data		<=	8'h00;
			txn_r.is_long	<=	1'b0;
			//or txn_r <= '{default: '0};
			
		end
		
		else
		begin
		// Register transactions on entry to register states
			unique case (state_next)
			
			S_INIT_LATCH:
			begin
				txn_r <= INIT_ROM[init_index];
			end
			
			S_TXN_LATCH:
			begin
				txn_r.rs			<= host_rs;
				txn_r.data		<=	host_data;
				txn_r.is_long	<=	is_long_cmd(host_rs, host_data);
			end
			
			default: /* no operation */;
			endcase
		end
	end
	
	
	///////////////////////////////////////////////
	//Moore outputs
	//////////////////////////////////////////////
	always_comb
	begin
	// defaults
	lcd_rs			=	1'b0;
	lcd_rw			=	1'b0;
	lcd_e				=	1'b0;
	lcd_data_o		=	txn_r.data;
	lcd_data_oe		=	1'b1;
	
	//host ready only in IDLE and only after init completes
	host_ready	=	(current_state	==	S_IDLE)	&&	(init_done);
	
	unique case (current_state)
		S_BUS_SETUP:
		begin
			lcd_rs		=	txn_r.rs;
			lcd_data_o	=	txn_r.data;
			lcd_e			=	1'b0;
		end
			
		S_E_HIGH:
		begin
			lcd_rs		=	txn_r.rs;
			lcd_data_o	=	txn_r.data;
			lcd_e			=	1'b1;
		end
		
		S_E_LOW:
		begin
			lcd_rs		=	txn_r.rs;
			lcd_data_o	=	txn_r.data;
			lcd_e			=	1'b0;
		end
		default: /*keep defaults*/;
	endcase
	end
	
	
endmodule

