	niosv_modular_control_system u0 (
		.clk_clk         (<connected-to-clk_clk>),         //        clk.clk
		.pwm_out_conduit (<connected-to-pwm_out_conduit>), //    pwm_out.conduit
		.rst_n_reset_n   (<connected-to-rst_n_reset_n>),   //      rst_n.reset_n
		.spi_master_sclk (<connected-to-spi_master_sclk>), // spi_master.sclk
		.spi_master_mosi (<connected-to-spi_master_mosi>), //           .mosi
		.spi_master_miso (<connected-to-spi_master_miso>), //           .miso
		.spi_master_cs_n (<connected-to-spi_master_cs_n>)  //           .cs_n
	);

