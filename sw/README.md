# Software (Nios V)

This directory contains software used to control and validate the FPGA system through the Nios V soft processor.

The current workflow is based on a Platform Designer system that generates a `.sopcinfo` file, which is used to build a Board Support Package (BSP) and application.

---

## Structure

```text
sw/
├── app/           # Nios V application
│   ├── src/       # source files (main.c, etc.)
│   └── build/     # generated (not tracked)
└── bsp/           # Board Support Package (generated/configured)
```

---

## Workflow

The software flow follows these steps:

```text
Platform Designer (.qsys)
        ↓
Generate system → .sopcinfo
        ↓
Create BSP
        ↓
Create application
        ↓
Build (CMake)
        ↓
Run on hardware
```

---

## BSP Creation

```bash
niosv-bsp --create --sopcinfo=../pd/niosv_modular_control_system.sopcinfo --type=hal bsp/settings.bsp
```

---

## Application Creation

```bash
niosv-app --app-dir=app --bsp-dir=bsp --srcs=app
```

---

## Build

```bash
cmake -B build -S .
cmake --build build
```

---

## Current Status

* Nios V system successfully generated in Platform Designer
* BSP creation and configuration working
* Application builds successfully using CMake
* `main.c` executes correctly on hardware

### Verified Behavior

* `printf` output via JTAG UART
* loop execution (for / while)
* timing using `usleep`
* stable infinite loop operation

This establishes a working hardware/software baseline.

---

## Example Test Behavior

The current `main.c` performs:

* variable arithmetic validation
* loop execution tests
* delay/timing validation
* heartbeat counter in an infinite loop

This confirms:

* CPU execution
* memory operation
* timing behavior
* console output

---

## Next Steps

### PWM Integration

* instantiate PWM component in Platform Designer
* connect to interconnect
* assign base address
* regenerate system
* update BSP

### Software Control

* enable PWM register access in `main.c`
* write:

  * period
  * duty cycle
  * control register
  * apply register
* verify LED behavior

---

### SPI Integration

* finalize `spi_regs.sv`
* finalize `axi_lite_spi.sv`
* package as Platform Designer component
* integrate into system
* control from software

---

## Notes

* BSP must match the `.sopcinfo` file exactly
* rebuild BSP after modifying Platform Designer system
* build artifacts (`build/`) are not tracked
* software interacts with hardware through MMIO registers

---

## Design Role

Software is used to:

* validate hardware functionality
* exercise MMIO interfaces
* provide system-level testing
* bridge embedded and FPGA design

This layer enables full system integration and verification.
