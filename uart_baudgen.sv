
// Produces baud_x16_tick: which is 1 clock cycle pulse at buadrate * 16
//	Produces baud_x1_tick: can be useful for the TX FSM to move to next bit
// DEFAULT_DIV_X16 = round (50Mhz/(9600*16)) = 326
module uart_baudgen #(
	parameter int unsigned DIV_WIDTH		=	9,//slowest baud requires div_x16 to be 326
	parameter int unsigned CLK_HZ			=	50_000_000,
	parameter int unsigned DEFAULT_BAUD	=	9_600
)
(
	input	logic	clk,
	input	logic	rst_n,
	input	logic	en,		//enable tick generation
	
	//Runtime override baudrate: set to 0 to use default baudrate
	input		logic	[DIV_WIDTH-1:0]	div_x16,
	
	output	logic							baud_x16_tick,
	output	logic							baud_1x_tick
);

	//compute a rounded divider:
	function automatic longint unsigned calc_div_x16
	(
		input longint unsigned clk_hz,
		input	longint unsigned baud
	);
		longint unsigned denominator;
		longint unsigned numerator;
		begin
			if	(baud	==	0)
			begin
				calc_div_x16 = 1; //safe fallback in case a bug happens
			end
			
			else
			begin
				denominator =	baud * 16;
				//Rounded devision: round(a/b) => (a+(b/2) / b)
				//example: round(50Mhz/(9600*16)) = 326
				numerator	=	clk_hz + (denominator/2);
				calc_div_x16	=	numerator/denominator;
				//if, calculated dividing cycles is 0, 
				//set it to 1, so it will sample rx signal
				//every clock cycle as a safenet
				if(calc_div_x16 < 1)
					calc_div_x16 = 1;
			end
		end
	endfunction
	
	localparam	longint	unsigned	DEFAULT_DIV_X16_LONG_INT = calc_div_x16(CLK_HZ, DEFAULT_BAUD);
	
	//clamp helpers (curated values to avoid edge cases issues
	logic [DIV_WIDTH-1:0] div_req; //will become the requested divider (divider I tend to use, override or default)
	logic [DIV_WIDTH-1:0] div_eff; //effective divider (curates the divider so it's never zero)
	
	always_comb
	begin
		//select divider: runtime override if nonzero, else computer default
		div_req	=	(div_x16 != '0) ? div_x16 : DEFAULT_DIV_X16_LONG_INT[DIV_WIDTH-1:0];
		
		//Ensure divider is at least 1
		div_eff = (div_req <= 1) ? 'd1 : div_req;
	end

	logic [DIV_WIDTH-1:0]	cnt;
	logic [3:0]					sub16;
	
	always_ff	@(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
		begin
			cnt				<= '0;
			sub16				<= '0;
			baud_x16_tick	<=	1'b0;
			baud_1x_tick	<= 1'b0;
		end
		
		else
		begin
			//default: pulses low unlsess asserted this cycle
			baud_x16_tick	<= 1'b0;
			baud_1x_tick	<= 1'b0;
			
			if(en)
			begin
				if(cnt == (div_eff -1))
				begin
					cnt				<= '0;
					baud_x16_tick	<= 1'b1;
					
					//Generate 1x tick every 16 x16-ticks
					if(sub16 == 4'd15)
					begin
						sub16				<=	4'd0;
						baud_1x_tick	<=	1'b1;
					end
					else
					begin
						sub16	<= sub16 + 4'd1;
					end
				end
				
				else
				begin
					cnt	<=	cnt + 'd1;
				end
			end
		
			else
			begin
				//disabled: hold deterministic phase (everything resets after disabling
				cnt		<= '0;
				sub16		<=	'0;
			end
			
		end
	end

endmodule