
module niosv_modular_control_system (
	clk_clk,
	motor_pwm_pwm,
	motor_pwm_in1,
	motor_pwm_in2,
	led_pwm_raw,
	rst_n_reset_n,
	spi_master_sclk,
	spi_master_mosi,
	spi_master_miso,
	spi_master_cs_n);	

	input		clk_clk;
	input	[3:0]	motor_pwm_pwm;
	input	[3:0]	motor_pwm_in1;
	input	[3:0]	motor_pwm_in2;
	output	[3:0]	led_pwm_raw;
	input		rst_n_reset_n;
	output		spi_master_sclk;
	output		spi_master_mosi;
	input		spi_master_miso;
	output		spi_master_cs_n;
endmodule
