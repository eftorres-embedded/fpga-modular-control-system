
module niosv_modular_control_system (
	clk_clk,
	hex0_hex0,
	hex1_hex1,
	hex2_hex2,
	hex3_hex3,
	hex4_hex4,
	hex5_hex5,
	i2c_master_sda_in,
	i2c_master_sda_out,
	i2c_master_scl_in,
	i2c_master_scl_out,
	i2c_master_master_receiving_o,
	led_pwm_raw,
	motor_pwm_pwm,
	motor_pwm_in1,
	motor_pwm_in2,
	rst_n_reset_n,
	spi_master_sclk,
	spi_master_mosi,
	spi_master_miso,
	spi_master_cs_n,
	live_input_live_value);	

	input		clk_clk;
	output	[7:0]	hex0_hex0;
	output	[7:0]	hex1_hex1;
	output	[7:0]	hex2_hex2;
	output	[7:0]	hex3_hex3;
	output	[7:0]	hex4_hex4;
	output	[7:0]	hex5_hex5;
	input		i2c_master_sda_in;
	output		i2c_master_sda_out;
	input		i2c_master_scl_in;
	output		i2c_master_scl_out;
	output		i2c_master_master_receiving_o;
	output	[9:0]	led_pwm_raw;
	output	[1:0]	motor_pwm_pwm;
	output	[1:0]	motor_pwm_in1;
	output	[1:0]	motor_pwm_in2;
	input		rst_n_reset_n;
	output		spi_master_sclk;
	output		spi_master_mosi;
	input		spi_master_miso;
	output		spi_master_cs_n;
	input	[23:0]	live_input_live_value;
endmodule
