# ENG NOTEBOOK - I2C Custom Core Bring-Up

**Project:** fpga-modular-control-system  
**Date:** 2026-04-16  
**Workstream:** I2C / MPU-6500 bring-up foundation  
**Stage:** Custom byte-engine verification complete; wrapper integration next

---

## 1. Objective

Develop and verify a project-owned I2C master byte engine that is easier to inspect, modify, and integrate than the earlier vendor/IP-centered path, while preserving the repository’s modular peripheral philosophy.

Near-term hardware target:
- MPU-6500 on the self-balancing kit

Immediate milestone:
- complete protocol-level simulation of the custom core before building the software-visible register/MMIO layer

---

## 2. Background and Design Pivot

This workstream changed direction.

The earlier plan centered on integrating a third-party or vendor-origin I2C solution, then wrapping it with project-owned register and AXI4-Lite logic. That approach no longer reflects the current implementation branch.

The active branch now uses a **project-owned custom I2C master core** written specifically for this repository.

### Why the direction changed
The custom-core route provides several practical advantages for this phase of the project:

- simpler waveform-level inspection
- easier protocol debugging during bring-up
- cleaner ownership of the software-visible contract
- easier explanation in an FPGA/embedded portfolio context
- fewer integration unknowns while validating bus behavior

This change does **not** mean the previous exploration was wasted. The earlier work helped validate the board-level open-drain path and reduced uncertainty around the external electrical interface.

---

## 3. Current Design Summary

The current RTL block is a **byte-oriented, single-master I2C engine**.

Current file focus:
- `rtl/peripherals/i2c/core/i2c_master_core.sv`

Current verification focus:
- `tb/unit/i2c/tb_i2c_master_core.sv`

### Implemented command set
The custom core currently supports the following byte-engine commands:

- `START`
- `WR`
- `RD`
- `STOP`
- `RESTART`

This is intentionally a **protocol engine**, not yet a complete MMIO-visible peripheral.

### Current command interface
The core uses an explicit command handshake:

- `cmd`
- `cmd_valid_i`
- `cmd_ready_o`

Accepted command rules:
- `S_IDLE` accepts only `START_CMD`
- `S_HOLD` accepts:
  - `WR_CMD`
  - `RD_CMD`
  - `STOP_CMD`
  - `RESTART_CMD`

### Current status/result outputs
The core exposes:

- `done_tick_o`
- `ack_o`
- `ack_valid_o`
- `rd_data_valid_o`
- `bus_idle_o`
- `master_receiving_o`
- `cmd_illegal_o`

These signals were added to make later wrapper integration cleaner and to remove ambiguity during simulation.

---

## 4. Open-Drain Integration Convention

The design continues to use the already-debugged open-drain top-level convention.

Conceptually:

```systemverilog
assign GPIO[PIN_MPU_I2C_SCL] = scl_drive_low ? 1'b0 : 1'bz;
assign GPIO[PIN_MPU_I2C_SDA] = sda_drive_low ? 1'b0 : 1'bz;

assign scl_i = GPIO[PIN_MPU_I2C_SCL];
assign sda_i = GPIO[PIN_MPU_I2C_SDA];
```

For the custom core, the wrapper-side SDA behavior is intentionally explicit:

```systemverilog
assign sda = (master_receiving_o || sda_out) ? 1'bz : 1'b0;
assign scl = (scl_out) ? 1'bz : 1'b0;
```

### Interpretation
- `sda_out = 0` -> master drives SDA low
- `sda_out = 1` -> master releases SDA
- `scl_out = 0` -> master drives SCL low
- `scl_out = 1` -> master releases SCL
- `master_receiving_o = 1` -> wrapper must release SDA because the slave owns that phase

This keeps bus ownership clear during both read and write transactions.

---

## 5. Divider / Timing Behavior

The current core clamps the requested divider to a minimum safe value and latches the transaction timing at the start of a new transaction.

Current design intent:
- divider is captured at `START_CMD`
- the entire transaction uses that latched divider
- mid-transaction software changes do not alter bus timing unexpectedly

This is a deliberate choice to keep protocol timing stable.

### Current limitation
Clock stretching is **not** implemented yet.
`scl_in` is reserved for that future extension.

---

## 6. Verification Strategy

A self-checking unit testbench was written to validate the protocol engine before any MMIO or AXI4-Lite wrapper work.

The testbench models:
- open-drain SDA/SCL behavior
- pull-up / released-bus behavior through tri-state resolution
- a simple slave that can:
  - ACK or NACK write transactions
  - source read data bits onto SDA
- legal and illegal command launches

This provides a focused protocol-level verification stage before system integration.

---

## 7. Verification Results

### Passing self-checking tests
The current simulation pass covers the following scenarios:

1. illegal `WR_CMD` in `S_IDLE`
2. illegal `START_CMD` in `S_HOLD`
3. `START -> WR(ACK) -> STOP`
4. `START -> WR(NACK) -> STOP`
5. `START -> WR(ACK) -> RESTART -> RD(last/NACK) -> STOP`

Result:
- **all tests passed**

### Waveform evidence
```markdown
![I2C custom core waveform](img/2026-04-16-tb_i2c_coreV1_wave.png)
```

Repo path:
- `docs/notebook/img/2026-04-16-tb_i2c_coreV1_wave.png`

### Transcript / pass evidence
```markdown
![I2C custom core simulation pass](img/2026-04-16-tb_i2c_coreV1_pass.png)
```

Repo path:
- `docs/notebook/img/2026-04-16-tb_i2c_coreV1_pass.png`


The I2C workstream has now moved from a vendor-core integration plan to a custom project-owned byte-engine implementation.

Current status:
- custom core implemented
- open-drain convention preserved
- self-checking simulation completed
- representative command sequences verified
- ready for wrapper/register integration


## 2026-04-19 — `i2c_regs` Completion

### Objective

Complete the software-visible register wrapper for the I2C byte engine and verify that the wrapper correctly enforces the intended command contract between software and the underlying I2C master core.

### Design Intent

The `i2c_regs` block was implemented as a compact MMIO-facing wrapper around the byte-oriented I2C master core. The design intent for V1 was to keep the interface explicit, predictable, and easy to debug in both software and waveforms.

Three principles guided the implementation:

1. **Polling-first operation**  
   Status is presented as live state rather than sticky event bookkeeping. Software is expected to poll readiness and completion state directly.

2. **Action-oriented command issue**  
   `REG_CMD` is treated as a launch register, not retained configuration state. A command exists only for the cycle in which software issues a valid write.

3. **No internal command queue**  
   The wrapper does not buffer multiple commands. Software must sequence START, WR, RD, RESTART, and STOP explicitly and may only launch a new command when the core reports that it is ready.

This approach keeps ownership clear: the wrapper handles register semantics and command gating, while software remains responsible for transaction sequencing.

### Register Philosophy

The register map was intentionally kept small and byte-transaction focused:

- `REG_STATUS` exposes live engine state
- `REG_DIVISOR` programs bus timing
- `REG_TXDATA` stages the transmit byte
- `REG_RXDATA` holds the most recently completed received byte
- `REG_CMD` launches byte-level bus actions and carries the `rd_last` qualifier for read termination

The wrapper stores only the minimum persistent state required for software interaction:

- transmit staging byte
- receive holding byte
- programmed divisor

All protocol progress information comes directly from the core as live status.

### Interface Contract

The wrapper follows the project MMIO request/response convention:

- one accepted request produces one response
- responses are held until `rsp_ready`
- decode and access violations return `rsp_err`
- command launch is permitted only when the I2C core is ready in the same cycle

This makes the software contract explicit and prevents ambiguous behavior.

The following accesses are intentionally rejected:

- reads of `REG_CMD`
- writes to read-only locations
- `REG_CMD` writes that do not include byte lane 0
- `REG_CMD` writes while the core is not ready

This behavior prevents partial-write launches, stale command interpretation, and accidental software-side misuse during integration.

### Architectural Role

```text
CPU / AXI-Lite bridge / generic MMIO master
                |
                v
          +-------------+
          |  i2c_regs   |
          |-------------|
          | REG_STATUS  |
          | REG_DIVISOR |
          | REG_TXDATA  |
          | REG_RXDATA  |
          | REG_CMD     |
          +-------------+
                |
                v
          +-------------+
          | i2c_master  |
          | byte engine |
          +-------------+
                |
                v
        open-drain SCL / SDA pins
```

This partition keeps the design clean:

- `i2c_regs` owns software visibility and command qualification
- `i2c_master` owns byte-level bus timing and protocol execution
- the top-level bus model and system integration remain outside the wrapper

### Why This Structure Was Chosen

For the first revision, a conservative wrapper is more valuable than a more automated but harder-to-debug interface. The selected structure provides:

- high observability during bring-up
- straightforward software control flow
- minimal hidden state
- simple waveform interpretation
- an easier path toward later extensions such as interrupts or higher-level transaction helpers

This is the right tradeoff for a foundational peripheral intended to be both practical and portfolio-ready.

---

## Verification Approach

### Testbench Philosophy

The `tb_i2c_regs` environment was written as a unit-level verification testbench for the register wrapper, not as a full-system or device-model simulation.

The philosophy of the testbench was:

1. verify MMIO behavior directly,
2. verify command gating rules at the wrapper boundary,
3. verify that issued commands correctly interact with the wrapped byte engine.

To keep the testbench focused, a lightweight slave-side behavioral model was used instead of a full sensor model. This made it possible to validate write-byte and read-byte behavior without introducing unnecessary protocol complexity.

### Bus Modeling Strategy

The testbench models `SDA` and `SCL` as resolved open-drain lines.

- the DUT drives the bus through its open-drain outputs,
- the slave-side helper drives only when needed,
- released lines return high through pull-up behavior.

This matches the intended electrical behavior closely enough for unit verification while remaining simple to reason about.

### What the Testbench Verifies

The completed testbench covers the expected V1 behavior:

- reset defaults
- divisor read/write behavior
- TX staging register read/write behavior
- rejection of an invalid partial `REG_CMD` write
- START launch
- rejection of a command while the core is not ready
- WR command with slave ACK
- RD command followed by master ACK
- RD command followed by master NACK when `rd_last = 1`
- STOP command returning the bus to idle

This gives confidence that both the software-visible contract and the wrapped byte-command path are functioning as intended.

### Testbench Refinements

During bring-up, the testbench was improved to make failures deterministic and easier to diagnose:

- long waits were converted to timeout-protected waits,
- the slave read helper was aligned to the active low phase of `SCL` at read start,
- checks were moved toward stable post-command observations rather than relying only on transient one-cycle pulses.

These changes improved regression reliability and eliminated false “hang” behavior caused by testbench timing assumptions.

### Verification Outcome

At the unit-test level, `i2c_regs` is now considered complete.

The wrapper correctly enforces the intended access rules, stages and returns software-visible data as expected, and launches I2C byte commands only under valid conditions. The associated testbench exercises both register semantics and wrapped command behavior with sufficient coverage for V1 integration.

---

## Design Assessment

The completed `i2c_regs` implementation meets the goals established for the first version of the I2C peripheral:

- compact register interface
- explicit software control
- predictable launch semantics
- low hidden complexity
- clear waveform-level observability

This makes it a strong foundation for the next stage of work, which is expected to include software driver/header creation, system-level integration, and live device testing.

## Current Status

**Completed**

- register wrapper implementation
- live status assembly
- action-based command launch path
- RX byte retention
- MMIO response handling
- dedicated unit testbench for wrapper and byte-command verification

**Next Steps**

- create C headers / helper functions for software access
- integrate the wrapper into the system interconnect
- perform real-device polling tests
- evaluate whether V2 should add interrupts or remain strictly polling-first

## I2C Robustness Investigation and V1.5 Core Improvement Plan

### Date
2026-04-24

### Context
The custom FPGA I2C master successfully communicates with the MPU-6500 over AXI4-Lite/MMIO. Low-level and higher-level software tests both confirmed:

- valid MMIO access to the I2C peripheral
- working divisor programming
- successful address probe at `0x68`
- successful register writes to `PWR_MGMT_1` and `PWR_MGMT_2`
- repeated-start register reads
- stable `WHO_AM_I = 0x70`
- repeated 14-byte burst reads of accel / temp / gyro data

Example successful bring-up results included:

- `I2C status = 0x00000003`
- `I2C debug reg = 0xDECAFBAD`
- `I2C divisor(after set) = 0x0000007D`
- `PROBE RESULT: address 0x68 ACKed`
- repeated `WHO_AM_I = 0x70` reads

### Problem Observed
Although the design works most of the time, occasional higher-level burst reads fail with:

```text
ERROR: burst read failed
```

After one of these failures, the bus may appear to stop making progress, and software may no longer observe normal clock activity until the transaction path is recovered.

### Electrical / Scope Observation Summary
Oscilloscope captures showed that the I2C bus is generally well-formed from a digital perspective:

- byte-group clock bursts are present
- SDA transitions mostly align with SCL low phases
- no severe ringing or obvious false-edge behavior was observed
- mild undershoot / small edge imperfections are visible, but not enough by themselves to explain the intermittent failures

Conclusion: the failures are more likely caused by transaction robustness / recovery corner cases than by gross signal-integrity problems.

### Root Cause Hypothesis
The most likely failure mechanism is a logic / recovery corner case, not a fundamentally broken bus.

The strongest candidates are:

1. **Core advances based on internal timing only**
   - The current V1 core releases SCL high, but does not use `scl_in` to verify the bus has actually risen before advancing state.
   - This makes the design sensitive to slow rise time, wiring capacitance, and marginal pull-up conditions.

2. **SDA is sampled at a fixed internal point**
   - The core samples SDA during read / ACK phases based on internal timing rather than confirmed bus-high timing.
   - This can create occasional mis-sampling even when the analog waveform looks mostly acceptable.

3. **`done_tick_o` occurs before the core is ready for the next command**
   - In the original V1 core, `done_tick_o` asserts at the end of `S_DATA_4`, before the FSM finishes `S_DATA_END` and returns to `S_HOLD`.
   - Software can therefore see “done” before `cmd_ready_o` is high again.

4. **No explicit abort / recovery path exists inside the core**
   - If a higher-level helper exits after a timeout or partial failure, the bus may not be driven back to a known STOP / IDLE condition.

These corner cases are consistent with the observed behavior:
- most transactions succeed
- failures are rare
- when a failure occurs, recovery is not always graceful

### Original V1 Core Review Notes
The following design characteristics were identified in the current `i2c_master_core.sv`:

- `cmd_ready_o` is only true in `S_IDLE` and `S_HOLD`
- `done_tick_o` is generated at the end of `S_DATA_4`
- `scl_in` is currently unused
- SDA sampling is tied to one internal timing point in `S_DATA_2`
- there is no `abort_i` or equivalent transaction recovery input

These observations indicate that the core assumes the real bus exactly follows the internal timing model, which is acceptable for an idealized V1 but fragile for real hardware.

### V1.5 Improvement Plan
A revised V1.5 version of the core was proposed with the following improvements:

#### 1. Add `abort_i`
Add a new input:

```systemverilog
input logic abort_i;
```

Purpose:
- allow software or wrapper logic to request a best-effort forced cleanup
- drive the core toward a STOP / IDLE recovery path after a timeout or failed transaction

#### 2. Align `done_tick_o` with real completion
Move `done_tick_o` later so it asserts at the end of `S_DATA_END`, closer to the point where the core is actually prepared to accept the next command.

Benefit:
- reduces race conditions between `done_tick_o` and `cmd_ready_o`
- makes the software contract cleaner

#### 3. Use `scl_in` as a bus-high qualifier
In phases where SCL is supposed to be high, do not advance state purely because the internal timer expired. Instead, require the bus to actually be high:

```systemverilog
high_phase_ready = scl_in;
```

Benefit:
- improves tolerance to slow rise time
- improves robustness with real wiring and pull-up behavior
- partially mitigates edge-rate / capacitance sensitivity even without full clock-stretch support

#### 4. Sample SDA only after confirmed SCL-high
Qualify SDA sampling with real bus-high timing rather than fixed internal timing alone.

Benefit:
- reduces risk of occasional ACK / data mis-sampling
- improves read reliability

#### 5. Add explicit abort states
Introduce dedicated abort states, for example:

- `S_ABORT_1`
- `S_ABORT_2`

These states perform a best-effort STOP-like cleanup sequence and return to `S_IDLE`.

### Expected Benefit of V1.5
The V1.5 changes are intended to improve real-world robustness without requiring a full clock-stretch implementation.

Expected benefits:

- fewer random burst-read failures
- better tolerance to non-ideal rise times
- clearer command-completion semantics
- cleaner recovery after a timeout or partial transaction failure

### Software Implication
Even with V1.5, software should still treat `cmd_ready_o` as the authoritative indication that the next command may be issued.

Recommended software rule:

- do not treat `done_tick_o` alone as permission to launch the next command
- always wait for `cmd_ready_o`

In addition, higher-level helper functions should converge to a single cleanup path on failure so the bus is always driven back toward STOP / IDLE as best as possible.

### Current Status
At the end of this investigation:

- the I2C block is confirmed working
- the MPU-6500 is confirmed responding at `0x68`
- burst reads are functional
- random failures remain infrequent but real
- V1.5 architectural changes have been identified and drafted as the next robustness step

### Next Actions
1. Integrate the V1.5 `i2c_master_core` changes
2. Retest higher-level burst reads at 100 kHz
3. Measure whether random failures are reduced or eliminated
4. Add software-accessible abort / recovery support in the wrapper/register layer
5. Only after logic recovery is improved, revisit any remaining electrical margin tuning if needed

