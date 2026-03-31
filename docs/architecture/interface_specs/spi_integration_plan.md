# SPI Integration Plan

## Purpose
This document defines how the SPI peripheral is integrated into the FPGA Modular Control System.

## Architecture
- Vendor protocol engine: third-party open-source SPI core
- Register/control layer: `spi_regs.sv`
- Bus layer: `axi_lite_spi.sv`

## Rationale
A third-party SPI core is used for the protocol engine to accelerate bring-up and reduce reinvention of low-level SPI timing logic.
Project effort is focused on:
- MMIO/software contract
- AXI4-Lite integration
- verification
- system-level composition

## Source Ownership
Vendor source:
- `rtl/peripherals/spi/vendor/opencores_verilog_spi/trunk/...`

Project source:
- `rtl/peripherals/spi/axi_lite_spi.sv`
- `rtl/peripherals/spi/regs/spi_regs.sv`

## Licensing
The vendor SPI core retains its original license and attribution.
Project wrapper and register logic remain separate.