# FPGA Modular Control System (DE10-Lite)

Modular FPGA-based control system built on the Intel MAX 10 (DE10-Lite), focused on reusable peripheral design, AXI4-Lite integration, and system-level architecture.

This project demonstrates FPGA system design principles including:

* memory-mapped peripheral interfaces
* protocol engine integration (SPI, UART, PWM)
* separation between datapath, control, and bus layers
* scalable RTL organization for SoC-style systems

## Overview

The system is organized as a collection of modular peripherals integrated through a consistent architecture. Each peripheral is designed to be reusable and independently testable.

## Architecture

Each peripheral follows a layered model:

AXI4-Lite
↓
Register Layer (MMIO contract)
↓
Core Engine (protocol/datapath)
↓
External Interface (pins / signals)

This structure enables reuse, easier verification, and clear software-hardware boundaries.

## Peripherals

### PWM

* Modular PWM subsystem with timebase, compare logic, register interface, and AXI4-Lite wrapper
* Deterministic timing and configurable behavior

### SPI (In Progress)

* Uses a third-party open-source SPI core as the protocol engine
* Vendor core isolated under `rtl/peripherals/spi/vendor/`
* Project logic implemented in:

  * `axi_lite_spi.sv`
  * `regs/spi_regs.sv`

### UART

* RX/TX engines with configurable baud generation
* Designed for integration with FIFO and system interfaces

### LCD (HD44780)

* Parallel LCD controller with FIFO adapter
* Demonstrates bridging between fast logic and slow peripherals

## Verification

* Unit testbenches for individual modules (PWM, UART)
* Integration testbench (`tb_top_system.sv`)
* Waveform-based validation using Questa/ModelSim

## Tools

* Intel Quartus Prime (Lite)
* Platform Designer (Qsys)
* Questa / ModelSim
* SystemVerilog
* Nios V (planned integration)

## Repository Structure

rtl/
common/
peripherals/
pwm/
spi/
uart/
lcd/
top/

tb/
unit/
integration/

docs/
architecture/
notebook/
bringup/

sw/
mcu/
host_tools/

## Third-Party IP

SPI Verilog Interface

* Source: https://opencores.org/projects/spi_verilog_interface
* License: LGPL
* Used as protocol engine only
* Integrated via custom register and AXI4-Lite wrapper

## Status

Implemented:

* UART subsystem
* PWM subsystem (core, registers, AXI wrapper)
* LCD controller and adapter
* FIFO utilities

In Progress:

* SPI integration and validation
* System-level integration

Planned:

* Nios V integration
* Additional peripherals (I2C, ADC)

## Purpose

This project serves as a reusable FPGA system framework and a demonstration of modular RTL design and system integration.
