# PWM Peripheral

Modular PWM subsystem designed for precise timing control and integration into AXI4-Lite systems.

## Architecture

AXI4-Lite
↓
pwm_regs.sv
↓
pwm_core_ip.sv
↓
timebase and compare logic

## Components

Core:

* pwm_timebase.sv
* pwm_compare.sv
* pwm_core_ip.sv

Control:

* regs/pwm_regs.sv

Bus:

* axi_lite_pwm.sv

Integration:

* pwm_subsystem.sv

## Features

* configurable period and duty cycle
* deterministic timing behavior
* separation of datapath and control

## Design Focus

* reusable PWM engine
* clear software interface
* scalable integration model
