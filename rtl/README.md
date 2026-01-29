# rtl/

Synthesizable HDL source code.

## What goes here
- SystemVerilog / VHDL intended to be synthesized
- Reusable IP blocks
- Top-level FPGA designs

## Structure
- common/        Shared primitives (reset, sync, FIFOs, timers)
- bus/           Bus fabric and MMIO adapters
- peripherals/   Device IP (UART, PWM, GPIO, LCD, etc.)
- top/           Top-level integration modules

## What does NOT go here
- Testbenches
- Simulation-only helpers
- Generated files
