
module niosv_modular_control_system (
	clk_clk,
	rst_n_reset_n,
	spi_master_sclk,
	spi_master_mosi,
	spi_master_miso,
	spi_master_cs_n,
	pwm_module_pwm_channel_pwm_out);	

	input		clk_clk;
	input		rst_n_reset_n;
	output		spi_master_sclk;
	output		spi_master_mosi;
	input		spi_master_miso;
	output		spi_master_cs_n;
	output	[9:0]	pwm_module_pwm_channel_pwm_out;
endmodule
