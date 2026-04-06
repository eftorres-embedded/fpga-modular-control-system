	component niosv_modular_control_system is
		port (
			clk_clk         : in  std_logic := 'X'; -- clk
			pwm_out_conduit : out std_logic;        -- conduit
			rst_n_reset_n   : in  std_logic := 'X'; -- reset_n
			spi_master_sclk : out std_logic;        -- sclk
			spi_master_mosi : out std_logic;        -- mosi
			spi_master_miso : in  std_logic := 'X'; -- miso
			spi_master_cs_n : out std_logic         -- cs_n
		);
	end component niosv_modular_control_system;

	u0 : component niosv_modular_control_system
		port map (
			clk_clk         => CONNECTED_TO_clk_clk,         --        clk.clk
			pwm_out_conduit => CONNECTED_TO_pwm_out_conduit, --    pwm_out.conduit
			rst_n_reset_n   => CONNECTED_TO_rst_n_reset_n,   --      rst_n.reset_n
			spi_master_sclk => CONNECTED_TO_spi_master_sclk, -- spi_master.sclk
			spi_master_mosi => CONNECTED_TO_spi_master_mosi, --           .mosi
			spi_master_miso => CONNECTED_TO_spi_master_miso, --           .miso
			spi_master_cs_n => CONNECTED_TO_spi_master_cs_n  --           .cs_n
		);

