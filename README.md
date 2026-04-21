# FPGA Modular Control System

DE10-Lite / MAX 10 system with a Nios V soft processor, AXI4-Lite/MMIO peripherals, SystemVerilog RTL, and project-owned C drivers.

## Whole-system block diagram

```text
Host PC
  |
  |  Quartus / Programmer / JTAG UART Console
  v
+-------------------------------------------------------------------+
|                       DE10-Lite / MAX 10                          |
|                                                                   |
|  +-------------------------------------------------------------+  |
|  |                 Platform Designer System                    |  |
|  |                                                             |  |
|  |  +------------------+     +------------------------------+  |  |
|  |  | Nios V CPU       |<--->| On-Chip Memory               |  |  |
|  |  +--------+---------+     +------------------------------+  |  |
|  |           |                                                 |  |
|  |           +-------> JTAG UART                               |  |
|  |           |                                                 |  |
|  |           v                                                 |  |
|  |      AXI4-Lite / MMIO interconnect                          |  |
|  +-----------+----------------------+--------------------------+  |
|              |                      |                             |
|              |                      |                             |
|              v                      v                             |
|      +---------------+      +---------------+                     |
|      | SPI wrapper   |      | I2C wrapper   |                     |
|      | + regs        |      | + regs        |                     |
|      +-------+-------+      +-------+-------+                     |
|              |                      |                             |
|              v                      v                             |
|       Vendor SPI core        Custom I2C byte engine               |
|              |                      |                             |
|              |                      +--------------------+        |
|              |                                           |        |
|              v                                           v        |
|         ADXL345 on-board                         self_balancing_io|
|                                                   board wrapper   |
|                                                           |       |
|                                      +--------------------+----+  |
|                                      | MPU-6500 | TB6612 | Hall|  |
|                                      | IMU      | Motors | I/O |  |
|                                      +----------+--------+-----+  |
|                                                                   |
|      +----------------------+      +---------------------------+  |
|      | PWM raw subsystem    |      | PWM motor subsystem       |  |
|      | + regs + wrapper     |      | + regs + wrapper          |  |
|      +----------+-----------+      +-------------+-------------+  |
|                 |                                  |              |
|                 v                                  v              |
|              LED outputs                    motor control outputs |
|                                                                   |
|      +---------------------------+                                |
|      | Quadrature subsystem RTL  |                                |
|      | + regs + wrapper          |                                |
|      +-------------+-------------+                                |
|                    |                                              |
|                    v                                              |
|              encoder / hall feedback path                         |
+-------------------------------------------------------------------+
```

## Implemented work

| Area | Repo evidence | Current status |
|---|---|---|
| Soft processor system | `pd/niosv_modular_control_system.qsys`, `quartus/project/`, `sw/app/` | running on hardware |
| SystemVerilog peripheral RTL | `rtl/peripherals/pwm/`, `spi/`, `i2c/`, `quadrature/`, `uart/`, `lcd/` | active development tree |
| AXI4-Lite / MMIO integration | local wrapper files such as `axi_lite_spi.sv`, `axi_lite_i2c.sv`, `axi_lite_pwm*.sv`, `axi_lite_quadrature.sv` | used across project peripherals |
| Register-map ownership | local `regs/` directories and matching C headers in `sw/drivers/include/` | project-owned contract |
| Embedded C drivers | `sw/drivers/src/` and `sw/drivers/include/` | active in current app |
| SPI sensor bring-up | `sw/drivers/src/adxl345.c`, `sw/app/src/main.c` | ADXL345 path active |
| I2C sensor bring-up | `sw/drivers/src/mpu6500.c`, `sw/app/src/main.c` | MPU-6500 path active |
| PWM control | `rtl/peripherals/pwm/`, `sw/drivers/src/pwm_regs.c`, `motor_pwm.c` | LEDs and motors driven from software |
| Board/platform wiring | `rtl/platform/de10_lite/self_balancing_io.sv` | external IMU / motor / hall path mapped |
| Verification | `tb/unit/pwm/`, `tb/unit/spi/`, `tb/unit/i2c/` | unit benches present |
| Third-party IP integration | `rtl/peripherals/spi/vendor/opencores_verilog_spi/` | isolated behind project wrapper |

## Current hardware-facing paths

| Path | Software entry | Hardware/device |
|---|---|---|
| SPI | `sw/drivers/src/adxl345.c` | on-board ADXL345 |
| I2C | `sw/drivers/src/mpu6500.c` | external MPU-6500 |
| PWM raw | `sw/drivers/src/pwm_regs.c` | DE10-Lite LEDs |
| PWM motor | `sw/drivers/src/motor_pwm.c` | TB6612 motor path |

## Verification map

| Area | Testbench path |
|---|---|
| PWM | `tb/unit/pwm/` |
| SPI | `tb/unit/spi/` |
| I2C | `tb/unit/i2c/` |
| Integration | `tb/integration/` |

## Toolchain

| Area | Tools |
|---|---|
| HDL / simulation | SystemVerilog, Questa / ModelSim |
| FPGA integration | Quartus Prime, Platform Designer |
| Embedded software | Nios V tools, C, CMake |

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
