	component niosv_modular_control_system is
		port (
			clk_clk         : in  std_logic := 'X'; -- clk
			rst_n_reset_n   : in  std_logic := 'X'; -- reset_n
			pwm_out_conduit : out std_logic         -- conduit
		);
	end component niosv_modular_control_system;

	u0 : component niosv_modular_control_system
		port map (
			clk_clk         => CONNECTED_TO_clk_clk,         --     clk.clk
			rst_n_reset_n   => CONNECTED_TO_rst_n_reset_n,   --   rst_n.reset_n
			pwm_out_conduit => CONNECTED_TO_pwm_out_conduit  -- pwm_out.conduit
		);

