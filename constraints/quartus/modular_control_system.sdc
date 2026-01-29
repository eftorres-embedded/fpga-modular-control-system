#============================================================
# DE10-Lite / MAX 10 — SDC (current project)
# Top clock: MAX10_CLK1_50 only (50 MHz => 20 ns)
#============================================================

#------------------------
# Primary input clock
#------------------------
create_clock -name MAX10_CLK1_50 -period 20.000 [get_ports {MAX10_CLK1_50}]

#------------------------
# Generated clocks (PLL)
#------------------------
# Safe to keep now; becomes useful once you add a PLL.
derive_pll_clocks
derive_clock_uncertainty

#------------------------
# Asynchronous reset / async inputs
#------------------------
# KEY[0] is your active-low reset source (async to MAX10_CLK1_50)
set_false_path -from [get_ports {KEY[0]}]

# Other human inputs are also async (recommend synchronizers in RTL)
set_false_path -from [get_ports {KEY[1]}]
set_false_path -from [get_ports {SW[*]}]

# GPIO/Arduino are generally async unless you define a source-synchronous interface
set_false_path -from [get_ports {GPIO[*]}]
set_false_path -from [get_ports {ARDUINO_IO[*]}]

# Accelerometer interrupt pins are async if you use them
# set_false_path -from [get_ports {GSENSOR_INT[*]}]
