
module niosv_modular_control_system (
	clk_clk,
	pwm_out_conduit,
	rst_n_reset_n,
	spi_master_sclk,
	spi_master_mosi,
	spi_master_miso,
	spi_master_cs_n);	

	input		clk_clk;
	output		pwm_out_conduit;
	input		rst_n_reset_n;
	output		spi_master_sclk;
	output		spi_master_mosi;
	input		spi_master_miso;
	output		spi_master_cs_n;
endmodule
