	niosv_modular_control_system u0 (
		.clk_clk                       (<connected-to-clk_clk>),                       //        clk.clk
		.gpio_gpio_in                  (<connected-to-gpio_gpio_in>),                  //       gpio.gpio_in
		.gpio_gpio_out                 (<connected-to-gpio_gpio_out>),                 //           .gpio_out
		.gpio_gpio_oe                  (<connected-to-gpio_gpio_oe>),                  //           .gpio_oe
		.hex0_hex0                     (<connected-to-hex0_hex0>),                     //       hex0.hex0
		.hex1_hex1                     (<connected-to-hex1_hex1>),                     //       hex1.hex1
		.hex2_hex2                     (<connected-to-hex2_hex2>),                     //       hex2.hex2
		.hex3_hex3                     (<connected-to-hex3_hex3>),                     //       hex3.hex3
		.hex4_hex4                     (<connected-to-hex4_hex4>),                     //       hex4.hex4
		.hex5_hex5                     (<connected-to-hex5_hex5>),                     //       hex5.hex5
		.i2c_master_sda_in             (<connected-to-i2c_master_sda_in>),             // i2c_master.sda_in
		.i2c_master_sda_out            (<connected-to-i2c_master_sda_out>),            //           .sda_out
		.i2c_master_scl_in             (<connected-to-i2c_master_scl_in>),             //           .scl_in
		.i2c_master_scl_out            (<connected-to-i2c_master_scl_out>),            //           .scl_out
		.i2c_master_master_receiving_o (<connected-to-i2c_master_master_receiving_o>), //           .master_receiving_o
		.led_pwm_raw                   (<connected-to-led_pwm_raw>),                   //    led_pwm.raw
		.live_input_live_value         (<connected-to-live_input_live_value>),         // live_input.live_value
		.motor_pwm_pwm                 (<connected-to-motor_pwm_pwm>),                 //  motor_pwm.pwm
		.motor_pwm_in1                 (<connected-to-motor_pwm_in1>),                 //           .in1
		.motor_pwm_in2                 (<connected-to-motor_pwm_in2>),                 //           .in2
		.rst_n_reset_n                 (<connected-to-rst_n_reset_n>),                 //      rst_n.reset_n
		.spi_master_sclk               (<connected-to-spi_master_sclk>),               // spi_master.sclk
		.spi_master_mosi               (<connected-to-spi_master_mosi>),               //           .mosi
		.spi_master_miso               (<connected-to-spi_master_miso>),               //           .miso
		.spi_master_cs_n               (<connected-to-spi_master_cs_n>)                //           .cs_n
	);

