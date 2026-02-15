// pwm_timebase.sv
//
module pwm_timebase #(
	parameter	int	unsigned				CNT_WIDTH				=	32,
	parameter	logic		[CNT_WIDTH-1:0]	DEFAULT_PERIOD_CYCLES	=	5_000,
	parameter	int							RST_CNT_WHEN_DISABLED	=	1'b1
	)
	(
	input		logic clk,
	input		logic rst_n,
	
	input		logic	enable,
	
	//Active period in clk cycles. If period_cycles <2, module will clamp it to 2.
	input		logic	[CNT_WIDTH-1:0]	period_cycles,
	
	output		logic	[CNT_WIDTH-1:0]	cnt,
	output		logic					period_start,
	output		logic					period_end,

	output		logic	[CNT_WIDTH-1:0]	period_cycles_eff
	);
	
	
	logic [CNT_WIDTH-1:0] period_cycles_candidate;
	
	//Due to the logic, period can have an unsafe value, it shoulnd't be 0 or 1, 
	//We can't expect for the software to follow this so it will be inforced in hardware
	assign period_cycles_candidate		=	(period_cycles == '0)			? DEFAULT_PERIOD_CYCLES		:	period_cycles;
	assign period_cycles_eff			=	(period_cycles_candidate < CNT_WIDTH'(2)) ? CNT_WIDTH'(2)	:	period_cycles_candidate;
	
	//Pulses derived from current count
	assign period_start	=	enable && (cnt == 0);
	assign period_end	= 	enable && (cnt == (period_cycles_eff - CNT_WIDTH'(1)));
	
	always_ff @(posedge clk or negedge rst_n)
	begin
		if(!rst_n)
			cnt	<= '0;
		else
		begin
			if(!enable)
				begin
					if(RST_CNT_WHEN_DISABLED)
						cnt <= '0;
					else
						cnt <= cnt;
				end
			else
				begin
					if(cnt >= (period_cycles_eff - CNT_WIDTH'(1)))
						cnt <= '0;
					else
						cnt <= cnt + 1'b1;
				end
		end
	end
	

endmodule