# FPGA Modular Control System

I built this project around one main idea: reusable FPGA peripherals with a consistent structure, a predictable software interface, and a clean path from simulation to hardware bring-up.

The board is a DE10-Lite with a MAX 10 FPGA. The processor is Nios V. The point of the project is not just to make one design work on one board. The point is to build modules I can keep reusing, extend without rewriting everything, and integrate the same way each time.

## What I am building

This repo is a modular control platform with:
- SystemVerilog peripherals
- AXI4-Lite / MMIO register interfaces
- Nios V software drivers in C
- board-level integration for sensors, motors, and external IO

## Design rules I follow

Across peripherals, I try to keep the same structure:

```text
bus wrapper -> register block -> core engine -> board/device pins
```

That gives me:
- a repeatable integration method
- standardized register-map style
- cleaner software drivers
- easier verification and debug

## How I use vendor IP vs custom RTL

I do both.

I use vendor or third-party IP when the block is already a solved commodity piece and the real work is in wrapping it, controlling it, and integrating it into the system.

I write my own RTL when I want direct control over the protocol behavior, the interface contract, or the internal implementation.

Current examples in this repo:
- **SPI:** third-party SPI core behind my own register layer and AXI-Lite wrapper
- **I2C:** project-owned byte engine, register layer, and wrapper
- **PWM:** project-owned core, register files, adapters, and subsystem variants
- **Quadrature:** project-owned decoder path and MMIO wrapper structure

## Whole-system block diagram

```text
Host PC
  |
  +--> Quartus / Programmer
  +--> JTAG UART Console
  |
  v
+======================================================================+
|                        DE10-Lite / MAX 10                            |
|                                                                      |
|  +---------------------------------------------------------------+   |
|  |                 Platform Designer System                      |   |
|  |                                                               |   |
|  |   +-------------------+      +-----------------------------+  |   |
|  |   | Nios V CPU        |<---->| On-Chip Memory              |  |   |
|  |   +---------+---------+      +-----------------------------+  |   |
|  |             |                                                 |   |
|  |             +-------------> JTAG UART                         |   |
|  |             |                                                 |   |
|  |             v   AXI4-Lite / MMIO Interconnect                 |   |
|  |             +--------------+---------------+-------------+    |   |
|  |             |              |               |             |    |   |
|  |             |              |               |             |    |   |
|  |             v              v               v             |    |   |
|  |   +--------------+  +--------------+  +--------------+   |    |   |
|  |   | SPI wrapper  |  | I2C wrapper  |  | PWM raw      |   |    |   |
|  |   | + regs       |  | + regs       |  | subsystem    |   |    |   |
|  |   +------+-------+  +------+-------+  | + regs       |   |    |   |
|  |          |                 |          +------+-------+   |    |   |
|  |          v                 v                 |           |    |   |
|  |   Vendor SPI core   Custom I2C engine        v           |    |   |
|  |          |                 |            LED outputs      |    |   |
|  |          |                 |                             |    |   |
|  |          v                 v                             |    |   |
|  |   ADXL345 on-board   self_balancing_io                   |    |   |
|  |                            |                             |    |   |
|  |                            v                             |    |   |
|  |                        MPU-6500                          |    |   |
|  |                                                          |    |   |
|  |                                  +-------------------+   |    |   |
|  |                                  | PWM motor         |<--+    |   |
|  |                                  | subsystem         |        |   |
|  |                                  | + regs            |        |   |
|  |                                  +---------+---------+        |   |
|  |                                            |                  |   |
|  +--------------------------------------------|------------------+   |
|                                               v                      |
|                                   self_balancing_io -> TB6612        |
+======================================================================+
```

## What is implemented here

| Area | In this repo | Current state |
|---|---|---|
| Nios V system | Platform Designer system, Quartus project, software build | running on hardware |
| AXI4-Lite / MMIO peripherals | SPI, I2C, PWM, quadrature wrappers and regs | active structure in repo |
| PWM family | raw, motor, servo-oriented organization | LEDs and motor path used from software |
| SPI path | wrapper + regs + third-party core + ADXL345 driver | active |
| I2C path | custom byte engine + regs + MPU-6500 driver | active |
| Board wrapper | `self_balancing_io.sv` | active external hardware path |
| Verification | PWM, SPI, I2C unit benches | present under `tb/unit/` |

## Hardware-facing paths in the current app

| Path | Software side | Device / endpoint |
|---|---|---|
| SPI | `adxl345.c` | on-board ADXL345 |
| I2C | `mpu6500.c` | external MPU-6500 |
| PWM raw | `pwm_regs.c` | DE10-Lite LEDs |
| PWM motor | `motor_pwm.c` | TB6612 motor path |

## Repo map

```text
rtl/           synthesizable HDL
pd/            Platform Designer systems and component packaging
quartus/       Quartus project files
constraints/   SDC constraints
tb/            simulation sources
sw/            Nios V application and drivers
docs/          architecture notes, bring-up docs, notebooks
```
