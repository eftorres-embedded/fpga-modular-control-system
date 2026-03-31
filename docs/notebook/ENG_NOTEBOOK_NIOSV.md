# ENG NOTEBOOK - NIOS V BRING-UP

## Objective

Integrate a Nios V soft processor into the FPGA Modular Control System and validate basic software execution on hardware.

---

## Current Status

* Platform Designer system created successfully
* Nios V CPU instantiated and connected
* BSP generated
* Application built using CMake
* `main.c` executes correctly on hardware
* Console output verified (printf + timing + loops)

This establishes a working hardware/software baseline.

---

## System Configuration

### Platform Designer Components

* Nios V processor
* On-chip memory
* JTAG UART (for console output)
* System clock + reset

### Notes

* Initial system kept minimal to reduce integration complexity
* No custom peripherals connected yet (PWM/SPI integration next)

---

## Build Flow

### BSP Creation

```bash
niosv-bsp --create --sopcinfo=../pd/niosv_modular_control_system.sopcinfo --type=hal bsp/settings.bsp
```

### Application Creation

```bash
niosv-app --app-dir=app --bsp-dir=bsp --srcs=app
```

### Build

```bash
cmake -B build -S .
cmake --build build
```

---

## Software Validation

### Test Program (main.c)

The current test verifies:

* variable operations
* for loops
* while loops
* delays using `usleep`
* continuous execution via infinite loop

Example behavior:

* periodic prints using `printf`
* heartbeat counter increments
* timing verified via delay loops

### Observed Output

* console output stable
* timing behavior consistent
* no crashes or stalls

---

## Key Observations

### 1. Toolchain Behavior

* Requires Nios V command shell environment
* BSP must match `.sopcinfo` exactly
* CMake-based build flow works reliably once configured

---

### 2. Minimal System Strategy Works

Starting with:

* CPU
* memory
* JTAG UART

greatly simplifies initial bring-up.

Avoiding early peripheral integration reduces debugging complexity.

---

### 3. Hardware/Software Boundary Established

At this stage:

* hardware system is stable
* software can run and interact with system resources
* ready to introduce MMIO peripherals

---

## Known Working Baseline

This milestone represents:

* working CPU
* working memory system
* working console output
* working delay/timing behavior

This is the reference point for future debugging.

---

## Next Steps

### 1. PWM Integration

* instantiate PWM AXI-Lite component in Platform Designer
* connect to interconnect
* assign base address
* regenerate system
* update BSP

### 2. Software Control of PWM

* re-enable PWM register definitions in `main.c`
* write:

  * period
  * duty cycle
  * control register
  * apply register
* verify LED behavior

---

### 3. SPI Completion

* finalize `spi_regs.sv`
* finalize `axi_lite_spi.sv`
* validate register interface
* package as Platform Designer component
* integrate into system

---

### 4. System Expansion

* connect multiple peripherals to CPU
* verify address map consistency
* extend software tests

---

## Notes for Future Documentation

* capture memory map after PWM/SPI integration
* document register interface for each peripheral
* include example MMIO access patterns in C

---

## Summary

Nios V bring-up is complete and stable.

The project has transitioned from:

* standalone RTL modules

to:

* a working FPGA + embedded system

Next phase focuses on:

* CPU-controlled peripherals
* full system integration
