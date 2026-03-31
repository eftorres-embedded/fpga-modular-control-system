	component niosv_modular_control_system is
		port (
			clock_in_clk_clk     : in std_logic := 'X'; -- clk
			reset_in_rst_reset_n : in std_logic := 'X'  -- reset_n
		);
	end component niosv_modular_control_system;

	u0 : component niosv_modular_control_system
		port map (
			clock_in_clk_clk     => CONNECTED_TO_clock_in_clk_clk,     -- clock_in_clk.clk
			reset_in_rst_reset_n => CONNECTED_TO_reset_in_rst_reset_n  -- reset_in_rst.reset_n
		);

