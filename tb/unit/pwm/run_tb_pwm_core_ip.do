transcript file build/sim/logs/tb_pwm_core_ip.txt
transcript on

log -r /tb_pwm_core_ip/*
log -r /tb_pwm_core_ip/dut/*

run -all

quit -f