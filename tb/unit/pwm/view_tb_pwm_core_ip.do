# Add top-level TB signals
add wave -r /tb_pwm_core_ip/*

# Add DUT internal signals
add wave -r /tb_pwm_core_ip/dut/*

# Format preferences
radix decimal /tb_pwm_core_ip/cnt
radix decimal /tb_pwm_core_ip/dut/cnt

# Zoom to full simulation
wave zoom full