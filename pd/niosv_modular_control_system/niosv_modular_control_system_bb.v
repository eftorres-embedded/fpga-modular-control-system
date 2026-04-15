
module niosv_modular_control_system (
	clk_clk,
	i2c_gyro_sda_in,
	i2c_gyro_scl_in,
	i2c_gyro_sda_oe,
	i2c_gyro_scl_oe,
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
	input		i2c_gyro_sda_in;
	input		i2c_gyro_scl_in;
	output		i2c_gyro_sda_oe;
	output		i2c_gyro_scl_oe;
	output	[9:0]	led_pwm_raw;
	output	[1:0]	motor_pwm_pwm;
	output	[1:0]	motor_pwm_in1;
	output	[1:0]	motor_pwm_in2;
	input		rst_n_reset_n;
	output		spi_master_sclk;
	output		spi_master_mosi;
	input		spi_master_miso;
	output		spi_master_cs_n;
endmodule
