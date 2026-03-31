# SPI Peripheral

SPI peripheral integrated using a layered architecture with a third-party protocol engine.

## Architecture

AXI4-Lite
↓
spi_regs.sv
↓
spi_master.v (vendor core)
↓
SPI pins

## Design Strategy

The SPI protocol engine is sourced from an open-source Verilog implementation.

This approach:

* avoids re-implementing standard SPI timing logic
* focuses development effort on system integration and MMIO design
* accelerates bring-up

## Source Ownership

Vendor:

* `vendor/opencores_verilog_spi/trunk/`

Project:

* `regs/spi_regs.sv`
* `axi_lite_spi.sv`

## Features

* CPOL / CPHA configurable
* streaming-style handshake interface
* integrated into MMIO architecture

## Notes

Vendor code is isolated to maintain licensing clarity and allow future replacement.
