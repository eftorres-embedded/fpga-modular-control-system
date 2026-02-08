`timesace 1ns/1ps

module tb_pwm_compare;

	localparam int unsigned CTN_WIDTH = 32;
	
	//DUT inputs
	logic							enable;
	logic	[CNT_WIDTH-1:0]	cnt;
	logic	[CNT_WIDTH-1:0]	period_cycles_eff;
	logic	[CNT_WIDTH-1:0]	duty_cycles;
	
	//DUT output
	logic							pwm_raw;
	
	//DUT instantiation
	pwm_compare #(
	.CNT_WIDTH(CNT_WIDTH)
	)
	dut(
	.enable(enable),
	.cnt(cnt),
	.period_cycles_eff(period_cycles_eff),
	.duty_cycles(duty_cycles),
	.pwm_raw(pwm_raw)
	);
	
	//Helper: check one count value
	task automatic expect_pwm_at_cnt(
	input	int	unsigned cnt_i,
	input logic				expected //high or low at a specific cnt
	);
	
		begin
			cnt = CNT_WIDTH'(cnt_i);
			#1; //small settle time for combinational logic
			if(pwm_raw !=== expected)
			begin
				$fatal(
				1, "FAIL: enable%0b period=%0d duty%0d cnt=%0d expected_pwm=%0b got %0b,
				enable, period_cycles_eff, duty_cycles, cnt, expected, pwm_raw
				);
			end
		end
	endtask

	//Helper: seep cnt over one period and count "highs"
	task automatic expect_high_count_in_period(
		input int unsigned period_i,
		input int unsigned duty_i,
		input	int unsigned expected_highs
	);
	
		int unsigned highs;
		int unsigned i;
		
		begin
			period_cycles_eff = CNT_WIDTH'(period_i);
			duty_cycles			= CNT_WIDTH'(duty_i);
			
			highs = 0;
			for(i=0;i<period_i;i++)
			begin
				cnt = CNT_WIDTH'(i);
				#1;
				if(pwm_raw === 1'b1)
					highs++;
			end
			
			if(highs != expected_highs)
			begin
				$fatal(1,
					"FAIL: period=%0d duty=%0d expected_highs=%0d got_highs=%0d",
					period_i, duty_i, expected_highs, highs
					);
			end
			else
			begin
				$display("PASS: period=%0d duty=%0d highs=%0d", period_i, duty_i, highs);
			end
		end
	endtask
	
	initial 
	begin
		$display(" === tb_pwm_compare start ===");
		
		//Default int
		enable				= 1'b0;
		cnt					=	'0;
		period_cycles_eff	=	CNT_WIDTH'(10);
		duty_cycles			=	'0;
		
		//enable on
		enable = 1'b1;
		
		//TEST 1: duty=0 => always low
		expect_high_count_in_perido(10,0,0);
		
		//TEST 2: duty=5 => exactly 5 highs (cnt 0-5 low)
		expect_high_count_in_period(10,5,5)
		
		//TEST 3: spot-check edges: cnt=4 high, cnt=5 low
		duty_cycles = CNT_WIDTH'(5);
		expect_pwm_at_cnt(4,1'b1);
		expect_pwm_at_cnt(5,1'b0);
		
		//TEST 4: duty=period => always high
		expect_high_count_in_period(10,10,10);
		
		//TEST 5: duty>period staturates => always high
		expect_high_count_in_period(10,999,10);
		
		$display("=== tb_pwm_compare PASS ===");
		$finish;
	end

endmodule