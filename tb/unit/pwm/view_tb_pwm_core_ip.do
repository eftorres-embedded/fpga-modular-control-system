# Clock / control
add wave /tb_pwm_core_ip/clk
add wave /tb_pwm_core_ip/rst_n
add wave /tb_pwm_core_ip/enable

# Runtime inputs
add wave -radix decimal /tb_pwm_core_ip/period_cycles_i
add wave -radix decimal /tb_pwm_core_ip/duty_cycles_i
add wave /tb_pwm_core_ip/use_default_duty

# Core outputs
add wave -radix decimal /tb_pwm_core_ip/cnt
add wave /tb_pwm_core_ip/period_end
add wave /tb_pwm_core_ip/pwm_raw

# Internal effective period
add wave -radix decimal /tb_pwm_core_ip/dut/period_cycles_eff



wave zoom full