# FPGA Modular Control System

Modular FPGA-based control system designed for incremental integration of communication interfaces, control logic and peripheral devices.

This project focuses on building an extensible HDL architecture, this will allow to recycle this project to derive single-purpose designs. 


---

## Status

**Active development**

Currently implemented and tested:
- UART-based communication
- FIFO buffering
- Parallel HD44780 (1602) LCD interface
- Basic control and utility modules (counter, register, reset synchronization)
- Top-level system integration targeting the DE10-Lite board


Planned (not fully implemented yet):
- SPI peripheral interface
- PWM generation
- Quadrature encoder interface
- Memory-mapped I/O (MMIO)
- Nios V softcore integration


---

- **FPGA Board:** DE10-Lite (MAX 10)
- **Toolchain:** Quartus Prime
- **Language:** SystemVerilog

## Repository Structure

Current Structure (work in progress):

- `modular_control_system_top.sv` - Top-Level system integration
- `fifo_to_lcd_adapter.sv` - FIFO to LCD interface logic
- `hd44780_parallel_lcd.sv` - 1602 LCD controller
- `sync_fifo.sv` - FIFO implementation
- `register.sv`, `counter.sv` - Utility/control modules
- `reset_sync.sv`,  `signla_to_pulse.sv` - Reset and signal conditioning


As the project grows, modules me be reorganized into `rtl/`, `contraints/`, and  `docs/` directories

---

## Build and Usage

1. Open `modular_control_system.qpf` in Quartus Prime
2. Compile the project
3. Program the FPGA on the DE10-Lite board
4. Interact with the system via UART and observe output on the LCD

Exact UART parameters and command formats will be documented as the interface stabilizes.

---

## Design Goals

- Maintain clean, readable RTL
- Avoid board-specific assumptions where possible
- Support incremental feature development without major refactors
- Keep synthesis and simulation artifacts out of version control

---

## Notes

This repository reflects an evolving system. Interfaces and module boundaries may change
as new features are added and refined.