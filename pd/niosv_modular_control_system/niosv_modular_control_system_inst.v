	niosv_modular_control_system u0 (
		.clk_clk         (<connected-to-clk_clk>),         //        clk.clk
		.motor_pwm_pwm   (<connected-to-motor_pwm_pwm>),   //  motor_pwm.pwm
		.motor_pwm_in1   (<connected-to-motor_pwm_in1>),   //           .in1
		.motor_pwm_in2   (<connected-to-motor_pwm_in2>),   //           .in2
		.led_pwm_raw     (<connected-to-led_pwm_raw>),     //    led_pwm.raw
		.rst_n_reset_n   (<connected-to-rst_n_reset_n>),   //      rst_n.reset_n
		.spi_master_sclk (<connected-to-spi_master_sclk>), // spi_master.sclk
		.spi_master_mosi (<connected-to-spi_master_mosi>), //           .mosi
		.spi_master_miso (<connected-to-spi_master_miso>), //           .miso
		.spi_master_cs_n (<connected-to-spi_master_cs_n>)  //           .cs_n
	);

