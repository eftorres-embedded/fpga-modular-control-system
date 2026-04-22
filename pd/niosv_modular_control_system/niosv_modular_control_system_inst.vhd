	component niosv_modular_control_system is
		port (
			clk_clk                       : in  std_logic                     := 'X';             -- clk
			i2c_master_sda_in             : in  std_logic                     := 'X';             -- sda_in
			i2c_master_sda_out            : out std_logic;                                        -- sda_out
			i2c_master_scl_in             : in  std_logic                     := 'X';             -- scl_in
			i2c_master_scl_out            : out std_logic;                                        -- scl_out
			i2c_master_master_receiving_o : out std_logic;                                        -- master_receiving_o
			led_pwm_raw                   : out std_logic_vector(9 downto 0);                     -- raw
			motor_pwm_pwm                 : out std_logic_vector(1 downto 0);                     -- pwm
			motor_pwm_in1                 : out std_logic_vector(1 downto 0);                     -- in1
			motor_pwm_in2                 : out std_logic_vector(1 downto 0);                     -- in2
			rst_n_reset_n                 : in  std_logic                     := 'X';             -- reset_n
			spi_master_sclk               : out std_logic;                                        -- sclk
			spi_master_mosi               : out std_logic;                                        -- mosi
			spi_master_miso               : in  std_logic                     := 'X';             -- miso
			spi_master_cs_n               : out std_logic;                                        -- cs_n
			hex0_hex0                     : out std_logic_vector(7 downto 0);                     -- hex0
			hex1_hex1                     : out std_logic_vector(7 downto 0);                     -- hex1
			hex2_hex2                     : out std_logic_vector(7 downto 0);                     -- hex2
			hex3_hex3                     : out std_logic_vector(7 downto 0);                     -- hex3
			hex4_hex4                     : out std_logic_vector(7 downto 0);                     -- hex4
			hex5_hex5                     : out std_logic_vector(7 downto 0);                     -- hex5
			bcd_input_bcd_input           : in  std_logic_vector(23 downto 0) := (others => 'X')  -- bcd_input
		);
	end component niosv_modular_control_system;

	u0 : component niosv_modular_control_system
		port map (
			clk_clk                       => CONNECTED_TO_clk_clk,                       --        clk.clk
			i2c_master_sda_in             => CONNECTED_TO_i2c_master_sda_in,             -- i2c_master.sda_in
			i2c_master_sda_out            => CONNECTED_TO_i2c_master_sda_out,            --           .sda_out
			i2c_master_scl_in             => CONNECTED_TO_i2c_master_scl_in,             --           .scl_in
			i2c_master_scl_out            => CONNECTED_TO_i2c_master_scl_out,            --           .scl_out
			i2c_master_master_receiving_o => CONNECTED_TO_i2c_master_master_receiving_o, --           .master_receiving_o
			led_pwm_raw                   => CONNECTED_TO_led_pwm_raw,                   --    led_pwm.raw
			motor_pwm_pwm                 => CONNECTED_TO_motor_pwm_pwm,                 --  motor_pwm.pwm
			motor_pwm_in1                 => CONNECTED_TO_motor_pwm_in1,                 --           .in1
			motor_pwm_in2                 => CONNECTED_TO_motor_pwm_in2,                 --           .in2
			rst_n_reset_n                 => CONNECTED_TO_rst_n_reset_n,                 --      rst_n.reset_n
			spi_master_sclk               => CONNECTED_TO_spi_master_sclk,               -- spi_master.sclk
			spi_master_mosi               => CONNECTED_TO_spi_master_mosi,               --           .mosi
			spi_master_miso               => CONNECTED_TO_spi_master_miso,               --           .miso
			spi_master_cs_n               => CONNECTED_TO_spi_master_cs_n,               --           .cs_n
			hex0_hex0                     => CONNECTED_TO_hex0_hex0,                     --       hex0.hex0
			hex1_hex1                     => CONNECTED_TO_hex1_hex1,                     --       hex1.hex1
			hex2_hex2                     => CONNECTED_TO_hex2_hex2,                     --       hex2.hex2
			hex3_hex3                     => CONNECTED_TO_hex3_hex3,                     --       hex3.hex3
			hex4_hex4                     => CONNECTED_TO_hex4_hex4,                     --       hex4.hex4
			hex5_hex5                     => CONNECTED_TO_hex5_hex5,                     --       hex5.hex5
			bcd_input_bcd_input           => CONNECTED_TO_bcd_input_bcd_input            --  bcd_input.bcd_input
		);

