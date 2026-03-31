# FPGA Modular Control System (DE10-Lite)

Modular FPGA-based control system built on the Intel MAX 10 (DE10-Lite), focused on reusable peripheral design, AXI4-Lite integration, and system-level architecture.

This project demonstrates FPGA system design principles including:

* memory-mapped peripheral interfaces
* protocol engine integration (SPI, UART, PWM)
* separation between datapath, control, and bus layers
* scalable RTL organization for SoC-style systems

---

## Overview

The system is organized as a collection of modular peripherals integrated through a consistent architecture. Each peripheral is designed to be reusable, independently testable, and software-controllable through a memory-mapped interface.

The current system includes a Nios V soft processor integrated via Platform Designer, with a working C application (`main.c`) executing successfully on hardware.

---

## Architecture

Each peripheral follows a layered model:

```text
           +---------------------+
           |     AXI4-Lite       |
           | (CPU / Interconnect)|
           +----------+----------+
                      |
                      v
           +---------------------+
           |   Register Layer    |
           |   (MMIO contract)   |
           +----------+----------+
                      |
                      v
           +---------------------+
           |     Core Engine     |
           | (protocol/datapath) |
           +----------+----------+
                      |
                      v
           +---------------------+
           | External Interface  |
           |   (pins / signals)  |
           +---------------------+
```

This structure enables:

* reuse across projects
* clear separation of concerns
* straightforward software-hardware interaction
* easier debugging and verification

---

## System Architecture

### Current Baseline

* Nios V soft processor integrated in Platform Designer
* On-chip memory and JTAG UART operational
* C application (`main.c`) runs correctly on hardware

### Immediate Next Steps

* Instantiate PWM in Platform Designer and control it from software
* Complete SPI register + AXI4-Lite integration and expose it to the CPU

```text
                          FPGA Modular Control System
                     Current baseline + near-term expansion

    +---------------------------------------------------------------+
    |                       DE10-Lite / MAX 10                      |
    |                                                               |
    |   +--------------------+                                      |
    |   |      Nios V        |                                      |
    |   |   Soft Processor   |                                      |
    |   +---------+----------+                                      |
    |             |                                                 |
    |             v                                                 |
    |   +--------------------+                                      |
    |   | AXI/Avalon Fabric  |                                      |
    |   | (Platform Designer)|                                      |
    |   +---+----------+-----+                                      |
    |       |          |                                            |
    |       |          |                                            |
    |       v          v                                            |
    |  +---------+  +-------------+                                 |
    |  | On-Chip |  |  JTAG UART  |<------ Host PC / Terminal       |
    |  | Memory  |  |   Console   |                                 |
    |  +---------+  +-------------+                                 |
    |                                                               |
    |       Planned / In Progress CPU-Controlled Peripherals        |
    |                                                               |
    |       +-------------------+    +-------------------+          |
    |       |   PWM Peripheral  |    |   SPI Peripheral  |          |
    |       | AXI-Lite Wrapper  |    | AXI-Lite Wrapper  |          |
    |       | + Regs + Core     |    | + Regs + Vendor   |          |
    |       +---------+---------+    |   Core            |          |
    |                 |              +---------+---------+          |
    |                 |                        |                    |
    |                 v                        v                    |
    |            PWM Output Pins          SPI External Pins         |
    |                                                               |
    +---------------------------------------------------------------+
```

### Current Validation Path

```text
main.c
  -> printf / loops / usleep
  -> Nios V execution confirmed
  -> JTAG UART console output confirmed
```

### Near-Term Expansion Path

```text
main.c
  -> MMIO writes to PWM registers
  -> MMIO writes/reads to SPI registers
  -> software-driven peripheral validation
```

---

## Peripherals

### PWM

* Modular PWM subsystem with timebase, compare logic, register interface, and AXI4-Lite wrapper
* Deterministic timing and configurable behavior
* Next step: integrate into Platform Designer and control from Nios V software

---

### SPI (Integration in Progress)

* Uses a third-party open-source SPI core as the protocol engine
* Vendor core isolated under `rtl/peripherals/spi/vendor/`

Project-owned logic:

* `axi_lite_spi.sv`
* `regs/spi_regs.sv`

Current focus:

* finalize register interface
* complete AXI4-Lite integration
* expose SPI as a CPU-controlled peripheral

---

### UART

* RX/TX engines with configurable baud generation
* Designed for integration with FIFO and system interfaces
* System console currently uses JTAG UART via Nios V

---

### LCD (HD44780)

* Parallel LCD controller with FIFO adapter
* Demonstrates bridging between fast logic and slow peripherals

---

## Verification

* Unit testbenches for individual modules (PWM, UART)
* Integration testbench (`tb_top_system.sv`)
* Waveform-based validation using Questa/ModelSim

---

## Tools

* Intel Quartus Prime (Lite)
* Platform Designer (Qsys)
* Questa / ModelSim
* SystemVerilog
* Nios V (RISC-V soft processor, integrated and running)

---

## Repository Structure

```text
rtl/
  common/
  peripherals/
    pwm/
    spi/
    uart/
    lcd/
  top/

pd/
  *.qsys
  *.sopcinfo

tb/
  unit/
  integration/

docs/
  architecture/
  notebook/
  bringup/

sw/
  app/
  bsp/
```

---

## Third-Party IP

SPI Verilog Interface

* Source: https://opencores.org/projects/spi_verilog_interface
* License: LGPL
* Used as protocol engine only
* Integrated via custom register and AXI4-Lite wrapper

---

## Status

### Implemented

* UART subsystem (RTL)
* PWM subsystem (core, registers, AXI wrapper)
* LCD controller and adapter
* FIFO utilities
* Nios V system (Platform Designer)
* BSP + application build flow
* `main.c` execution verified on hardware

### In Progress

* SPI integration and validation
* PWM integration into Platform Designer
* software-driven peripheral control (MMIO)

### Planned

* Additional peripherals (I2C, ADC)
* extended system integration and testing

---

## Purpose

This project serves as a reusable FPGA system framework and a demonstration of:

* modular RTL design
* SoC-style system architecture
* hardware/software co-design
* embedded control of FPGA peripherals
