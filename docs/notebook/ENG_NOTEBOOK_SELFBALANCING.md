# Engineering Lab Notebook - Self-Balancing Robot Architecture (DE10-Lite, Nios V)

**Owner:** Eder Torres  
**Repo:** https://github.com/eftorres-embedded/fpga-modular-control-system  
**Board:** DE10-Lite (MAX 10)  
**CPU:** Nios V soft processor  
**Clock Assumption:** 50 MHz  
**Scope:** system architecture, control partitioning, sensor strategy, first bring-up roadmap for a simple self-balancing robot

---

## 2026-04-22 - Self-Balancing Robot Planning Entry

### Objective
Create a clear system-level plan for a first self-balancing robot using the existing DE10-Lite modular control platform.

The immediate architectural decision is:
- use the **MPU-6500** as the **main balancing sensor**
- keep the **ADXL345** available as a **secondary/reference accelerometer** for comparison and later validation
- keep the first balancing loop in **Nios V software**
- use the already integrated FPGA peripherals as the hardware control and debug backbone

---

### Current Hardware / Integration Baseline
The following subsystems are already part of the design direction and are intended to remain in the self-balancing platform:

- `niosv` soft processor as the control center
- `spi` peripheral
- `i2c` peripheral
- `motor_pwm` peripheral
- `led_pwm` peripheral
- `seg7_debug` peripheral
- `gpio` peripheral
- `jtag_uart` for software console/debug

External or board-connected devices:
- `MPU-6500` connected through `i2c`
- `ADXL345` connected through `spi`
- `LEDR[]` driven through `led_pwm`
- `SW[]` read through `gpio`
- `HEX5..HEX0` driven through `seg7_debug`
- `Motor 1` and `Motor 2` controlled from `motor_pwm`

---

## System Architecture

### High-Level Platform Diagram

```text
                                          Host PC
                                             |
                     Quartus Programmer / Ashling / JTAG UART Console
                                             |
                                             v
                                 +---------------------------+
                                 | USB-Blaster / JTAG / SLD  |
                                 +-------------+-------------+
                                               |
                                               v
+------------------------------------------------------------------------------------------+
|                               DE10-Lite / MAX 10 FPGA                                    |
|                                                                                          |
|                                  +--------------------+                                  |
|                                  |     clk / reset    |                                  |
|                                  +---------+----------+                                  |
|                                            |                                             |
|                                            v                                             |
|   +--------------------+        +----------------------+                                 |
|   |   On-Chip Memory   |<------>|       Nios V         |                                 |
|   +--------------------+        |  main control CPU    |                                 |
|                                 +----------+-----------+                                 |
|                                            |                                             |
|                                            v                                             |
|     +----------------------------------------------------------------------------------+ |
|     |                       AXI4-Lite / mixed AXI-Avalon fabric                        | |
|     +---+----------+-----------+-----------+------------+-------------+-----------+----+ |
|         |          |           |           |            |             |           |      |
|         v          v           v           v            v             v           v      |
| +-----------+ +---------+ +---------+ +---------+ +-----------+ +-----------+ +--------+ |
| | Motor PWM | | SPI IP  | | I2C IP  | | GPIO IP | |SEG7 DEBUG | | JTAG UART | |LED PWM | |
| |  s_axil   | | s_axil  | | s_axil  | | s_axil  | |  s_axil   | | Avalon-MM | | s_axil | |
| +-+------+--+ +----+----+ +----+----+ +----+----+ +-----+-----+ +-----+-----+ +---+----+ |
|   |      |         |           |           |            |             |           |      |
|   v      v         v           v           v            v             v           v      |
| Motor1 Motor2  +---------+ +---------+  +------+   +-----------+     host     +--------+ |
|                | ADXL345 | |MPU-6500 |  | SW[] |   | HEX5..HEX0|              | LEDR[] | |
|                | via SPI | | via I2C |  +------+   +-----------+              +--------+ |
|                +---------+ +---------+                                                   |
|                                                                                          |
|                                                                                          |
|                                                                                          |
|                                                                                          |
|                                                                                          |
|                                                                                          |
|                                                                                          |
|                                                                                          |
|                                                                                          |
|                                                                                          |
|                                                                                          |
+------------------------------------------------------------------------------------------+
```

### Control-Centric View (Nios V as the center)

```text
                                  +------------------+
                                  |      Nios V      |
                                  | control center   |
                                  +--------+---------+
                                           |
                    +----------------------+-----------------------+
                    |                      |                       |
                    v                      v                       v
              +-----------+          +-----------+          +-------------+
              |   SPI IP  |          |   I2C IP  |          |  JTAG UART  |
              +-----+-----+          +-----+-----+          +------+------+
                    |                      |                       |
                    v                      v                       v
              +-----------+          +-----------+          Host PC console
              | ADXL345   |          | MPU-6500  |
              | reference |          | main IMU  |
              +-----------+          +-----------+

                    +----------------------+-----------------------+
                    |                      |                       |
                    v                      v                       v
               +---------+           +-----------+           +------------+
               | GPIO IP |           | SEG7 DBG  |           |  LED PWM   |
               +----+----+           +-----+-----+           +------+-----+
                    |                      |                        |
                    v                      v                        v
                  SW[]                 HEX5..HEX0                LEDR[]

                                           |
                                           v
                                    +--------------+
                                    |  MOTOR PWM   |
                                    | 2 motor chs  |
                                    +------+-------+
                                           |
                                  +--------+--------+
                                  |                 |
                                  v                 v
                               Motor 1           Motor 2
```

### Balancing Data Path

```text
                          +----------------------+
                          |      MPU-6500        |
                          | accel + gyro + temp  |
                          +----------+-----------+
                                     |
                                     v
                                +---------+
                                | I2C IP  |
                                +----+----+
                                     |
                                     v
                              +--------------+
                              |    Nios V    |
                              | fixed-rate   |
                              | control loop |
                              +------+-------+
                                     |
                   +-----------------+-----------------+
                   |                                   |
                   v                                   v
         +-------------------+               +-------------------+
         | complementary     |               | debug / telemetry |
         | filter / estimator|               | JTAG / seg7 / LED |
         +---------+---------+               +-------------------+
                   |
                   v
         +-------------------+
         | balance control   |
         | first target: PD  |
         +---------+---------+
                   |
                   v
            +-------------+
            | motor_pwm   |
            | duty + dir  |
            +------+------+ 
                   |
          +--------+--------+
          |                 |
          v                 v
       Motor 1           Motor 2
```

### Sensor Ownership Diagram

```text
                           +------------------+
                           |      Nios V      |
                           +--------+---------+
                                    |
                +-------------------+-------------------+
                |                                       |
                v                                       v
         +--------------+                        +--------------+
         |   MPU-6500   |                        |   ADXL345    |
         | primary IMU  |                        | reference    |
         | used for     |                        | read later   |
         | balancing    |                        | for compare  |
         +------+-------+                        +------+-------+
                |                                       |
                | I2C                                   | SPI
                v                                       v
          tilt angle, rate,                        accel-only cross-
          gyro bias, accel                         check / validation
```

---

## Design Decision Summary

| Decision | Choice | Rationale |
|---|---|---|
| Main balancing sensor | `MPU-6500` | Provides both accelerometer and gyroscope data, which is the correct first sensor set for balancing |
| Secondary/reference sensor | `ADXL345` | Useful later for reference/comparison, but not required for the first closed-loop balance attempt |
| First control implementation | `Nios V software` | Fastest path to a working robot; easier tuning and debugging than moving filter/control into RTL too early |
| Motor control block | `motor_pwm` | Existing PWM/motor-control infrastructure already matches the project architecture |
| Software debug path | `jtag_uart` | Fastest way to inspect variables during bring-up |
| Front-panel debug | `seg7_debug` + `LEDR[]` + `SW[]` | Makes the robot debuggable without depending only on the PC console |
| Initial controller type | `PD` | Simpler and more stable for first bring-up than jumping directly into full PID |
| Estimator type | `complementary filter` | Practical first estimator using gyro + accel without unnecessary complexity |

---

## Why the MPU-6500 is the Main Sensor

The MPU-6500 is the correct first-choice balancing sensor because it combines:
- 3-axis accelerometer
- 3-axis gyroscope
- one digital interface path already planned through `i2c`

For a self-balancing robot, the most important signals are:
- **tilt angle estimate**
- **tilt angular rate**

An accelerometer alone can estimate gravity direction when the robot is relatively still, but balancing requires dynamic information during motion. The gyroscope fills that gap. Therefore, the MPU-6500 should own the main estimator and control loop.

The ADXL345 remains useful for:
- later cross-checking the accelerometer estimate
- comparing noise/response against the MPU-6500 accelerometer
- debug logging and reference plots

---

## First Control Architecture

### Intended Software Layers

```text
main.c
  |
  +-- platform init
  +-- peripheral init
  +-- imu calibration
  +-- fixed-rate control loop

sensor layer
  |
  +-- mpu6500.c / mpu6500.h
  +-- adxl345.c / adxl345.h   (reference only, later use)

estimator layer
  |
  +-- complementary filter
  +-- pitch angle estimate
  +-- pitch rate estimate

control layer
  |
  +-- PD controller
  +-- output clamp / deadband
  +-- motor command mapping

ui/debug layer
  |
  +-- jtag uart prints
  +-- seg7 page formatting
  +-- LED status indication
  +-- switch interpretation
```

### Proposed Runtime Loop

```text
1. Read MPU-6500 accel/gyro
2. Remove gyro bias
3. Compute accel-based pitch estimate
4. Update complementary filter
5. Compute control output (PD first)
6. Saturate / apply deadband / safety limits
7. Write motor_pwm commands
8. Update seg7 / LED / optional console output
9. Repeat at fixed rate
```

---

## Requirements / Constraints

### Functional Requirements
- Robot must estimate pitch angle from the MPU-6500
- Robot must estimate pitch rate from the MPU-6500 gyro
- Robot must drive both motors through `motor_pwm`
- Robot must expose useful debug state over `jtag_uart`
- Robot must expose essential runtime values on `seg7_debug`
- Switches must remain available for mode control through `gpio`

### First-Build Constraints
- First version should prioritize **bring-up speed** over elegance
- First version should avoid moving estimator/control into RTL
- First version should avoid overcomplicated filtering
- First version should keep the ADXL345 outside the primary control loop
- First version should allow easy motor disable / safe-stop behavior

### Safety Constraints
- Motors should default to off or coast/brake-safe state at startup
- If the IMU read fails, motor output should be disabled
- If the robot angle exceeds a configurable threshold, control output should be forced off
- Bring-up should start with assisted/tethered tests, not free-standing floor tests

---

## Bring-Up Phases

## Phase 1 - IMU truth model and sign convention

### Goal
Make sure the software understands the robot orientation correctly before any balancing attempt.

### Tasks
- [ ] define which MPU axis is robot pitch
- [ ] define which gyro axis corresponds to pitch rate
- [ ] verify sign convention for forward tilt / backward tilt
- [ ] verify sign convention for motor correction direction
- [ ] calibrate gyro bias at startup while robot is still
- [ ] print raw and converted IMU values over `jtag_uart`

### Deliverable
A test program that reports stable MPU-6500 readings and clearly identifies tilt sign and rate sign.

---

## Phase 2 - Fixed-rate estimator

### Goal
Create a stable pitch estimate using the MPU-6500.

### Tasks
- [ ] define loop period `dt`
- [ ] compute accelerometer-only pitch estimate
- [ ] compute gyro-integrated pitch estimate
- [ ] implement complementary filter
- [ ] confirm estimator responds correctly to hand tilt tests
- [ ] display filtered angle and gyro rate on `seg7_debug`

### Deliverable
A repeatable pitch estimate that tracks slow tilt and short motion without obvious drift or instability.

---

## Phase 3 - Motor characterization

### Goal
Understand how the drivetrain responds before closing the balance loop.

### Tasks
- [ ] identify minimum duty to overcome static friction
- [ ] verify left motor polarity
- [ ] verify right motor polarity
- [ ] verify brake vs coast behavior
- [ ] measure left/right mismatch
- [ ] define a safe output clamp for indoor testing

### Deliverable
A simple mapping from signed control effort to per-motor commands with known deadband and saturation behavior.

---

## Phase 4 - First balance controller

### Goal
Stand up the first real balancing loop.

### Initial control law

```text
u = Kp * theta_est + Kd * gyro_pitch_rate
```

### Tasks
- [ ] implement PD controller
- [ ] add output clamp
- [ ] add motor deadband compensation if needed
- [ ] add tilt-angle kill threshold
- [ ] add software arm/disarm mode
- [ ] verify correction direction while robot is held by hand

### Deliverable
A controlled tethered test where the robot pushes back in the correct direction when tilted.

---

## Phase 5 - Assisted balance test

### Goal
Achieve the first short balancing event in a safe and controlled way.

### Tasks
- [ ] run with support boom / hand assist
- [ ] tune `Kp`
- [ ] tune `Kd`
- [ ] reduce oscillation
- [ ] verify no immediate runaway on small disturbances
- [ ] capture console output for test notes

### First success criterion
- robot remains upright for a short interval with assistance
- correction direction is stable
- controller can recover from a small hand disturbance

---

## Phase 6 - Hardening and expansion

### Goal
Turn the first balancing demo into a more complete platform.

### Later additions
- [ ] add ADXL345 comparison logging
- [ ] add wheel encoders
- [ ] add outer velocity or position loop
- [ ] store calibration values in nonvolatile memory later if needed
- [ ] consider moving selected math into RTL only after software behavior is proven

---

## Proposed Switch / LED / 7-Segment Usage

### Switch usage through `gpio`

Suggested initial meanings:
- `SW[0]` = motor arm/disarm
- `SW[1]` = hold motors off / debug-only mode
- `SW[2]` = enable estimator printouts
- `SW[9:7]` or `SW[9:6]` = page select for 7-segment debug

### LED usage through `led_pwm`

Suggested initial meanings:
- heartbeat / alive status
- armed state
- IMU valid state
- estimator running
- fault indicator

### 7-segment usage through `seg7_debug`

Suggested page set:
- page 0 = filtered pitch angle
- page 1 = gyro pitch rate
- page 2 = control output
- page 3 = left motor duty
- page 4 = right motor duty
- page 5 = fault / state bits

This preserves the role of the current UI hardware as a live debug aid during motion testing.

---

## Suggested Initial Software Module Breakdown

```text
sw/
  app/
    src/
      main.c
      self_balancing_app.c
      self_balancing_app.h
      imu_estimator.c
      imu_estimator.h
      balance_ctrl.c
      balance_ctrl.h
      debug_pages.c
      debug_pages.h

  drivers/
    src/
      mpu6500.c
      adxl345.c
      motor_pwm.c
      seg7_debug_regs.c
      gpio_regs.c
      i2c_regs.c
      pwm_regs.c

    include/
      mpu6500.h
      adxl345.h
      motor_pwm.h
      seg7_debug_regs.h
      gpio_regs.h
      i2c_regs.h
      pwm_regs.h
```

---

## Test Strategy

## Test 1 - MPU-6500 static read test
**Expected:** stable accel and gyro values when robot is stationary  
**Pass if:** bias is repeatable and sign conventions are understood

## Test 2 - Pitch estimation by hand
**Expected:** filtered pitch angle changes in the correct sign and returns near zero when upright  
**Pass if:** no obvious estimator sign mistake remains

## Test 3 - Motor direction validation
**Expected:** forward tilt command produces the intended corrective motor direction  
**Pass if:** both motors respond with the expected correction polarity

## Test 4 - Held-in-air controller test
**Expected:** controller pushes back against manual tilt without runaway  
**Pass if:** system opposes tilt and stays inside safe output limits

## Test 5 - Assisted floor test
**Expected:** robot makes a short controlled attempt to stabilize  
**Pass if:** brief balance or near-balance behavior is observed without immediate uncontrolled launch

---

## Known Risks / Likely Debug Areas
- IMU axis mapping mistakes
- gyro sign convention mistakes
- motor sign convention mistakes
- too much console printing slowing the loop
- insufficient fixed-rate timing discipline
- motor deadband and left/right mismatch
- noise entering the estimator from vibration
- mechanical center of mass too low or too far from the axle

---

## Practical Guidance for the First Real Attempt

The shortest path to first success is:
1. make the **MPU-6500-only** estimator work first
2. verify motor direction in software with the robot held by hand
3. run a **PD** loop, not full PID
4. use `jtag_uart`, `seg7_debug`, `LEDR[]`, and `SW[]` as live bring-up tools
5. leave the ADXL345 outside the control loop until the robot already shows balancing behavior

---

## Conclusion
This design should treat the **MPU-6500 as the primary balancing IMU** and the **ADXL345 as a later reference sensor**.

The existing FPGA modular control platform already contains the correct structure for a first self-balancing robot:
- Nios V at the center
- AXI4-Lite-connected peripheral control blocks
- dedicated IMU interfaces through `i2c` and `spi`
- reusable `motor_pwm` block for actuation
- `jtag_uart`, `seg7_debug`, `led_pwm`, and `gpio` for practical bring-up and runtime debugging

The recommended first milestone is not “perfect autonomous balance,” but rather:

**a safe, assisted test where the robot estimates tilt correctly and applies corrective motor action in the right direction.**

Once that is achieved, gain tuning, encoder feedback, and higher-performance architecture work can follow.

---

## Next Steps
- [ ] Create `self_balancing_app.c/.h`
- [ ] Finalize MPU-6500 axis/sign convention in software
- [ ] Add complementary filter implementation
- [ ] Add PD controller implementation
- [ ] Define 7-segment page encoding for estimator/controller variables
- [ ] Run held-by-hand correction-direction test
- [ ] Document first assisted balance attempt with screenshots / console logs
