	niosv_modular_control_system u0 (
		.clk_clk                        (<connected-to-clk_clk>),                        //                    clk.clk
		.pwm_module_pwm_channel_pwm_out (<connected-to-pwm_module_pwm_channel_pwm_out>), // pwm_module_pwm_channel.pwm_out
		.rst_n_reset_n                  (<connected-to-rst_n_reset_n>),                  //                  rst_n.reset_n
		.spi_master_sclk                (<connected-to-spi_master_sclk>),                //             spi_master.sclk
		.spi_master_mosi                (<connected-to-spi_master_mosi>),                //                       .mosi
		.spi_master_miso                (<connected-to-spi_master_miso>),                //                       .miso
		.spi_master_cs_n                (<connected-to-spi_master_cs_n>)                 //                       .cs_n
	);

