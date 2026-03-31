# ENG NOTEBOOK - SPI

## Status
SPI is the next active peripheral workstream.

## Goal
Integrate an SPI peripheral into the modular control system using the project’s standard peripheral structure:
- vendor/core isolation
- local register file
- AXI4-Lite wrapper
- top-level subsystem integration

## Design Decision
Instead of writing the SPI protocol engine from scratch, this project uses an existing open-source Verilog SPI core as the low-level shift/timing engine.

Reasoning:
- reduces time spent re-deriving standard SPI timing logic
- allows focus on SoC integration and software-visible interface design
- keeps the reusable architecture of this repository consistent

## Third-Party Core Strategy
Vendor RTL is isolated under:
`rtl/peripherals/spi/vendor/opencores_verilog_spi/trunk/`

Project-owned integration logic remains separate:
- `rtl/peripherals/spi/axi_lite_spi.sv`
- `rtl/peripherals/spi/regs/spi_regs.sv`

This separation is intentional to:
- preserve attribution and licensing clarity
- avoid mixing vendor code with project code
- make future core replacement easier

## Planned Integration Layers
1. SPI vendor core
2. SPI register file
3. AXI4-Lite wrapper
4. System/top-level integration
5. Software test through Nios V

## Initial Tasks
- review vendor SPI handshake and timing assumptions
- define software-visible register map
- connect register layer to vendor core
- add status and interrupt strategy
- create basic smoke test

## Notes
The first objective is functional bring-up, not feature completeness.
Advanced items such as FIFOs, interrupts, and extended transaction support can be added after baseline integration works.