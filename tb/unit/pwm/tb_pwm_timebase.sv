`timescale 1ns/1ps

module tb_pwm_timebase;

	logic clk;
	
	initial clk = 1'b0;
	always #10 clk = ~clk;
	
	initial 
	begin
		$display("TB start");
		repeat (5) @(posedge clk);
		$display("TB saw 5 rising edges");
		$finish;	
	end
	
endmodule