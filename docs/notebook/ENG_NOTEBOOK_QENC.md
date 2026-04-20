# Engineering Lab Notebook - Quadrature Decoder Peripheral (DE10-Lite, Nios V, AXI4-Lite)

**Owner:** Eder Torres  
**Repo:** `fpga-modular-control-system`  
**Board:** DE10-Lite  
**Clock Assumption:** 50 MHz  
**Scope:** Dedicated quadrature decoder peripheral for motor encoder feedback, integrated with Nios V through AXI4-Lite

---

## 2026-04-20 — Quadrature Decoder Peripheral Proposal

### Objective
Design a dedicated FPGA quadrature decoder peripheral to interface rotary encoder signals with the Nios V soft processor through AXI4-Lite.

The purpose of this block is to move encoder edge tracking and position accumulation into hardware so the Nios V only needs to read position, velocity-related data, and status/interrupt flags. This keeps the real-time signal path in FPGA fabric while preserving software control and observability.

This proposal is intended as a cleaner FPGA-oriented alternative to the timer-centric quadrature decoder style commonly shown in microcontroller vendor documentation.

---

## Background / Motivation

A timer-based quadrature block is a useful conceptual reference because it combines:

- a quadrature decoder
- a position counter
- optional capture/timer resources
- interrupt generation

However, that structure is optimized for a **microcontroller timer peripheral**, where one timer block is reused for many functions.

For this FPGA project, a better architectural choice is to make the **quadrature decoder and position counter the center of the design**, and treat timing/capture logic as an auxiliary feature instead of the main organizing principle.

The FPGA should continuously process A/B encoder edges in hardware, while AXI4-Lite should only provide control, readback, and interrupt handling.

---

## High-Level Design Direction

### Proposed architecture

```text
encoder A/B inputs
      |
      v
+--------------------------+
| input synchronizers      |
| optional glitch filter   |
+--------------------------+
      |
      v
+--------------------------+
| quadrature transition    |
| decoder                  |
| - forward step           |
| - reverse step           |
| - illegal transition     |
+--------------------------+
      |
      v
+--------------------------+
| signed position counter  |
+--------------------------+
      |
      +----------------------------+
      |                            |
      v                            v
+------------------+      +----------------------+
| snapshot / delta |      | optional timebase /  |
| latch            |      | edge-period capture  |
+------------------+      +----------------------+
      |                            |
      +-------------+--------------+
                    |
                    v
          +----------------------+
          | AXI4-Lite regs + IRQ |
          +----------------------+
                    |
                    v
                  Nios V
```

### Key design philosophy

The real-time signal chain is:

```text
A/B pins -> synchronizer/filter -> transition decoder -> position counter
```

The software-visible path is:

```text
AXI4-Lite -> control / status / readback / interrupt service
```

This separation keeps the critical path deterministic and hardware-driven.

---

## Why a dedicated quadrature block is preferred

### Reason 1: cleaner FPGA partitioning
A dedicated quadrature block maps more naturally into RTL than a generic timer/capture/output-compare peripheral. The essential hardware behavior is encoder state tracking, not generic timer multiplexing.

### Reason 2: easier verification
A dedicated block can be tested directly for:

- valid forward transitions
- valid reverse transitions
- illegal transitions
- correct signed count behavior
- optional filtering
- optional sample-period velocity latch

This is simpler than proving the behavior of a large timer mode matrix.

### Reason 3: better robotics fit
For motor feedback and self-balancing work, the most important outputs are:

- position
- direction
- velocity estimate
- input health / transition errors

A generic timer output module or compare/PWM channel is not part of the immediate requirement.

---

## Platform Integration Notes

This peripheral is intended to fit the current Nios V design style already being used in the project:

- custom FPGA peripheral logic in RTL
- register layer separated from core datapath
- AXI4-Lite wrapper at the bus boundary
- Platform Designer used for system assembly
- software-visible control and monitoring from the Nios V side

Expected integration model:

```text
quadrature_core
    ->
quadrature_regs
    ->
axi_lite_quadrature
    ->
Platform Designer component
    ->
Nios V system
```

A single interrupt output is expected to be sufficient for V1.

---

## Requirements / Constraints

### Functional requirements
- Decode quadrature encoder inputs A and B
- Support position tracking in hardware
- Provide direction information
- Detect illegal transitions
- Provide software-readable registers over AXI4-Lite
- Provide interrupt support
- Support reset/clear/home behavior

### Non-functional requirements
- Keep the real-time decode path independent from CPU polling
- Keep the peripheral bus-friendly and portable
- Keep the internal architecture bus-agnostic where possible
- Preserve a clean path for future expansion (index input, velocity improvement, multiple instances)

### Initial project constraints
- FPGA clock assumed to be 50 MHz
- First version should be simple enough to simulate thoroughly
- First version should support one encoder channel pair
- First version should integrate with Nios V through AXI4-Lite
- First version should prioritize correctness and observability over feature count

---

## Proposed V1 Feature Set

### V1 core features
- 2-channel quadrature decode (`A`, `B`)
- x1 / x2 / x4 decode mode selection
- 2-FF or 3-FF synchronizers on inputs
- optional digital glitch filter / debounce
- signed 32-bit position counter
- direction indication
- illegal transition flag
- software clear / preload / home capability
- interrupt output
- AXI4-Lite register interface

### V1 optional-but-good features
- programmable sample-period latch of `delta_count`
- snapshot register to capture coherent readback
- optional index/Z input placeholder
- overflow / underflow flags

---

## Design Decisions

| Decision | Choice | Rationale |
|---|---:|---|
| Core organization | Dedicated quadrature peripheral | Cleaner than a timer-centric MCU-style block |
| Bus interface | AXI4-Lite | Matches current Nios V portability direction |
| Position width | 32 bits signed | Large enough for initial use, simple software access |
| Decode modes | x1/x2/x4 | Covers common encoder use cases |
| Input handling | synchronizers + optional filter | Protect against async inputs and noisy edges |
| Velocity approach (V1) | sampled delta count | Simpler than full reciprocal-period estimator |
| Interrupt model | single IRQ output | Simple integration with Nios V platform interrupts |
| Error detection | illegal transition flag | Important for debug and signal integrity checks |

---

## Decoder Behavior

### State transition method

The decoder should evaluate previous and current encoder states:

```text
prev = {A_prev, B_prev}
curr = {A_curr, B_curr}
```

Valid forward sequence:

```text
00 -> 01 -> 11 -> 10 -> 00
```

Valid reverse sequence:

```text
00 -> 10 -> 11 -> 01 -> 00
```

From this:

- valid forward step: `position++`
- valid reverse step: `position--`
- same state: no movement
- invalid jump (example `00 -> 11`): set illegal transition flag

### Why illegal transition detection matters
Illegal transitions are useful because they can indicate:

- input noise
- insufficient synchronization/filtering
- encoder wiring issues
- mechanical chatter
- missed intermediate states

This makes the peripheral more useful during bring-up than a simple counter-only design.

---

## Velocity Estimation Strategy

### V1 approach
For the initial version, velocity should be estimated using a programmable sample interval.

At each sample event:

```text
delta_count = position_now - position_prev
```

This value is latched into a software-readable register.

### Why this is the preferred V1 choice
This method is:

- simple to implement
- easy to verify
- easy to consume in software
- good enough for first closed-loop testing

Later versions may add:

- last-edge period capture
- reciprocal-period velocity estimation
- hybrid low-speed / high-speed estimator

But that is not necessary for V1 bring-up.

---

## Proposed Register Map (V1)

| Offset | Name | Access | Description |
|---|---:|---|---|
| `0x00` | `REG_CTRL` | R/W | enable, reset/clear, mode select, filter enable |
| `0x04` | `REG_STATUS` | R/W1C | direction, illegal transition, overflow, sample ready |
| `0x08` | `REG_POSITION` | R | signed live position counter |
| `0x0C` | `REG_DELTA` | R | sampled position delta |
| `0x10` | `REG_SAMPLE_PERIOD` | R/W | programmable sample interval in FPGA clocks |
| `0x14` | `REG_FILTER_CFG` | R/W | debounce / filter configuration |
| `0x18` | `REG_PRELOAD` | R/W | preload value for counter |
| `0x1C` | `REG_CMD` | W | clear counter, load preload, snapshot |
| `0x20` | `REG_IRQ_EN` | R/W | interrupt enable mask |
| `0x24` | `REG_IRQ_STATUS` | R/W1C | interrupt pending status |

### Notes
- `REG_STATUS` and `REG_IRQ_STATUS` should use sticky W1C bits where appropriate
- `REG_POSITION` should be read coherently
- `REG_CMD` is preferred over overloading control bits with pulse semantics

---

## Suggested Bitfield Direction

### `REG_CTRL`
| Bit | Name | Description |
|---|---:|---|
| `[0]` | `ENABLE` | enables quadrature decode |
| `[2:1]` | `DECODE_MODE` | x1/x2/x4 selection |
| `[3]` | `FILTER_EN` | enables digital input filter |
| `[4]` | `SWAP_AB` | swaps A and B interpretation |
| `[5]` | `INVERT_A` | optional input polarity invert |
| `[6]` | `INVERT_B` | optional input polarity invert |

### `REG_STATUS`
| Bit | Name | Description |
|---|---:|---|
| `[0]` | `DIR` | current direction |
| `[1]` | `ILLEGAL_TRANSITION` | invalid state jump detected |
| `[2]` | `OVERFLOW` | counter overflow occurred |
| `[3]` | `UNDERFLOW` | counter underflow occurred |
| `[4]` | `SAMPLE_READY` | new delta sample available |

---

## RTL Partition Proposal

### Files to create

```text
rtl/peripherals/quadrature/
  core/
    quadrature_decoder_core.sv
    quadrature_filter.sv           (optional separate file)
    quadrature_timebase.sv         (optional, for sample tick)
  regs/
    quadrature_regs.sv
  subsystems/
    quadrature_subsystem.sv
  axi_lite_quadrature.sv
```

### File responsibilities

#### `quadrature_decoder_core.sv`
Owns:
- synchronized A/B inputs
- optional filter
- previous/current state decode
- step generation
- direction tracking
- position counter
- illegal transition pulse
- optional sampled delta

#### `quadrature_regs.sv`
Owns:
- register decode
- control register storage
- command decoding
- status flags
- W1C handling
- IRQ generation

#### `quadrature_subsystem.sv`
Owns:
- connection between register layer and core
- bus-agnostic internal wiring
- top-level peripheral composition

#### `axi_lite_quadrature.sv`
Owns:
- AXI4-Lite slave interface
- translation into internal MMIO request/response channel

---

## Proposed Software Contract

### Basic software sequence
```text
1. Configure REG_SAMPLE_PERIOD
2. Configure REG_FILTER_CFG if needed
3. Configure REG_CTRL
4. Enable IRQs if needed
5. Read REG_POSITION / REG_DELTA / REG_STATUS during runtime
6. Clear sticky flags with W1C writes
```

### Example conceptual use
```text
- enable x4 decode
- filter enabled
- sample every 50,000 clocks (1 ms at 50 MHz)
- read position each control cycle
- read delta_count each control cycle
- handle illegal transition interrupt if asserted
```

---

## Verification Plan

### Unit tests for decoder core
- [ ] T1 forward sequence increments counter
- [ ] T2 reverse sequence decrements counter
- [ ] T3 no-change state produces no count
- [ ] T4 illegal transition raises flag
- [ ] T5 reset clears state and counter
- [ ] T6 x1/x2/x4 modes behave as expected
- [ ] T7 input synchronizer/filter prevents chatter from causing extra counts
- [ ] T8 preload/load command works

### Register-layer tests
- [ ] T9 AXI/MMIO writes update control registers correctly
- [ ] T10 W1C status behavior works
- [ ] T11 interrupt mask and pending logic works
- [ ] T12 position and delta readback are correct
- [ ] T13 command register pulses behave correctly

### Integration tests
- [ ] T14 connect simulated encoder waveform to subsystem
- [ ] T15 verify Nios-visible position updates through AXI4-Lite
- [ ] T16 verify IRQ assertion on illegal transition
- [ ] T17 verify sampled delta updates at requested interval

---

## Bring-up / Debug Plan

### Signals to observe in simulation / waveform
- raw encoder `A`, `B`
- synchronized `A`, `B`
- filtered `A`, `B`
- previous state
- current state
- forward step pulse
- reverse step pulse
- illegal transition pulse
- signed position counter
- delta latch
- IRQ pending bits

### Hardware debug plan
Once integrated into Platform Designer and top-level wiring, use Signal Tap to inspect:

- encoder inputs at FPGA pins
- synchronized/filter outputs
- step pulses
- position counter
- status/IRQ signals

This should make it straightforward to separate wiring issues from decode logic issues during bring-up.

---

## Future Extensions

### V2 candidates
- index / Z input support
- edge timestamp capture
- low-speed reciprocal-period velocity estimation
- snapshot registers for coherent multiword readback
- multiple quadrature channels

### V3 candidates
- hardware RPM scaling support
- threshold/window compare interrupts
- position compare events
- tighter coupling with motor-control loop
- possible streaming or DMA-friendly sample export

---

## Initial Conclusion

The proposed quadrature peripheral should be implemented as a **dedicated FPGA block**, not as a direct copy of a timer-based microcontroller peripheral.

The recommended architecture is:

```text
dedicated quadrature decode
+ signed position count
+ sampled delta latch
+ status / IRQ
+ AXI4-Lite register interface
```

This is the cleanest match to:

- FPGA fabric strengths
- Nios V software integration
- Platform Designer system assembly
- future motor-control expansion


---

