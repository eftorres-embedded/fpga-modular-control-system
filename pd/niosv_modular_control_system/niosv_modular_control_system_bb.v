
module niosv_modular_control_system (
	clk_clk,
	pwm_module_pwm_channel_pwm_out,
	rst_n_reset_n,
	spi_master_sclk,
	spi_master_mosi,
	spi_master_miso,
	spi_master_cs_n);	

	input		clk_clk;
	output	[9:0]	pwm_module_pwm_channel_pwm_out;
	input		rst_n_reset_n;
	output		spi_master_sclk;
	output		spi_master_mosi;
	input		spi_master_miso;
	output		spi_master_cs_n;
endmodule
