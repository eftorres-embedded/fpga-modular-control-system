//pwm_compare.sv
//
//Pure combinational PWM compare:
// -pwm_raw = enable && (cnt < duty_eff)
//
// Precondition/Contract
// -cnt counts 0 to period_cycles_eff-1
// -period_cycles_eff is already clamped >= 2 by pwm_timebase
// -duty_cycles may be any value; we saturate to [0 to period_cycles_eff]
//

module pwm_compare #(
	parameter int unsigned CNT_WIDTH = 32
	)
	(
	input	logic							enable,
	
	//From pwm_timebase
	input		logic	[CNT_WIDTH-1:0]	cnt,
	input		logic	[CNT_WIDTH-1:0]	period_cycles_eff,
	
	//Requested duty-cycle in clk cycles (0-period). Saturated in hardware.
	input		logic	[CNT_WIDTH-1:0]	duty_cycles,
	
	//Raw PWM output (to be post-processed by higher-level abstraction: sign-mag, complementary, etc)
	output	logic							pwm_raw
	);
	
	logic	[CNT_WIDTH-1:0] duty_eff;
		
	//Saturate duty to [0 to period_cycles_eff]
	// - If duty > perido then treat as 100%
	// - duty == period then always high
	assign duty_eff = (duty_cycles >= period_cycles_eff) ? period_cycles_eff : duty_cycles;
	
	//Core compare
	assign pwm_raw = (!enable) ? 1'b0 : (cnt < duty_eff);
	
	
endmodule