`timescale 1ns/1ps

module tb_pwm_timebase;

	// We match the parameters of our DUT
	localparam	int	unsigned			CNT_WIDTH				=	32;
	localparam	logic	[CNT_WIDTH-1:0]	DEFAULT_PERIOD_CYCLES	=	5_000;


	///DUT inputs////////////////////////
	logic clk;
	logic rst_n;
	logic enable;
	logic [CNT_WIDTH-1:0] period_cycles;


	///DUT outputs///////////////////////
	logic [CNT_WIDTH-1:0] cnt;
	logic period_start;
	logic period_end;

	//clock generation: 50 MHz (20 ns period)
	initial clk = 1'b0;
	always #10 clk = ~clk;

	//Instantiate DUT
	pwm_timebase #(
		.CNT_WIDTH(CNT_WIDTH),
		.DEFAULT_PERIOD_CYCLES(DEFAULT_PERIOD_CYCLES),
		.RST_CNT_WHEN_DISABLED(1'b1))
		dut (
		.clk(clk),
		.rst_n(rst_n),
		.enable(enable),
		.period_cycles(period_cycles),
		.cnt(cnt),
		.period_start(period_start),
		.period_end(period_end)
		);

	//Helpers
	task automatic wait_clks(input int n);
		repeat (n) @(posedge clk);
	endtask

	//period_end is combinational from cnt.
	//edge-toedge measurment with for/join_any was used to avoid sampling races
	//at @(posedge clk)
	task automatic expect_period_end_spacing(input int expected);
	int between;
	begin
		// Start at a clean pulse edge
		wait (!period_end);
		@(posedge period_end);

		between = 0;

		// Count clk edges until the NEXT period_end edge happens
		fork : measure
		begin : clk_counter
			forever begin
			@(posedge clk);
			between++;
			end
		end

		begin : wait_next_pulse
			wait (!period_end);
			@(posedge period_end);
		end
		join_any

		disable measure;

		if (between != expected)
		$fatal(1, "FAIL: expected %0d cycles between period_end pulses, got %0d",
				expected, between);
		else
		$display("PASS: period_end spacing = %0d cycles", expected);
	end
	endtask



	//Test sequence
	initial
	begin
		$display("=== tb_pwm_timebase start ===");

		//init inputs
		rst_n			=	 1'b0;
		enable			=	1'b0;
		period_cycles	=	'0;

		//reset
		wait_clks(5);
		rst_n = 1'b1;
		wait_clks(2);
		
		//DEMO: short period so waveforms show activity
		$display("DEMO: short period waveform activity");
		period_cycles = CNT_WIDTH'(8);
		enable        = 1'b1;

		// Let it run for a few periods (8 cycles each)
		wait_clks(40);

		// Change period on the fly to show effect (will take effect immediately in this core)
		$display("DEMO: change period to 12");
		period_cycles = CNT_WIDTH'(12);
		wait_clks(48);

		// Optional: disable/enable once to show reset behavior in the wave
		$display("DEMO: disable/enable");
		@(negedge clk); enable = 1'b0;
		wait_clks(5);
		@(negedge clk); enable = 1'b1;
		wait_clks(24);


		////////////////////////////////////////////////////////////
		//////////////TEST 1: period_cycles = 10////////////////////
		////////////////////////////////////////////////////////////
		$display("TEST 1: period_cycles = 10 cadence");
		period_cycles	=	CNT_WIDTH'(10);
		enable			=	1'b1;

		wait_clks(1);
$display("DBG: period_cycles=%0d cand=%0d eff=%0d cnt=%0d term=%0d period_end=%0b",
         period_cycles,
         dut.period_cycles_candidate,
         dut.period_cycles_eff,
         cnt,
         (dut.period_cycles_eff - CNT_WIDTH'(1)),
         period_end);


		expect_period_end_spacing(10);


		/////////////////////////////////////////////////////////////////
		///TEST 2: period_cycles = 0, which should trigger the default //
		/////////////////////////////////////////////////////////////////
		$display("TEST 2: period_cycles = 0 uses DEFAULT (%0d)", int'(DEFAULT_PERIOD_CYCLES));
		period_cycles = '0;
		expect_period_end_spacing(int'(DEFAULT_PERIOD_CYCLES));


		////////////////////////////////////////////////////////
		///TEST 3: period_cycles = 1, which should clamp to 2 //
		////////////////////////////////////////////////////////
		$display("TEST 3: period_cycles = 1 clamps to 2");
		period_cycles = CNT_WIDTH'(1);
		expect_period_end_spacing(2);


		/////////////////////////////////////////////////////////////////
		///TEST 4: disable reset cnt (since RST_CNT_WHEN_DISABLED = 1 //
		/////////////////////////////////////////////////////////////////
		$display("TEST 4: disable resets cnt");
		period_cycles = CNT_WIDTH'(10);

		wait_clks(3);    	//cnt should advance 3 cycles

		@(negedge clk);
		enable	=	1'b0;	//disable the counter
	
		@(posedge clk);		//give DUT one clock edge to aplly !enable behavior
		@(negedge clk);

		if(cnt !== '0)
			$fatal(1, "FAIL: expected cnt == 0 after disable, got %0d", cnt);
		else
			$display("PASS: cnt reset on disable");
		
		$display(" === tb_pwm_timebase PASS ===");


		$finish;
	end

endmodule