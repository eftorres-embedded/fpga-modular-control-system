
module niosv_modular_control_system (
	clk_clk,
	led_pwm_raw,
	motor_pwm_pwm,
	motor_pwm_in1,
	motor_pwm_in2,
	rst_n_reset_n,
	spi_master_sclk,
	spi_master_mosi,
	spi_master_miso,
	spi_master_cs_n);	

	input		clk_clk;
	output	[9:0]	led_pwm_raw;
	input	[1:0]	motor_pwm_pwm;
	input	[1:0]	motor_pwm_in1;
	input	[1:0]	motor_pwm_in2;
	input		rst_n_reset_n;
	output		spi_master_sclk;
	output		spi_master_mosi;
	input		spi_master_miso;
	output		spi_master_cs_n;
endmodule
