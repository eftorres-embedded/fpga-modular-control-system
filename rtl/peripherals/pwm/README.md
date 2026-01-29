# PWM Peripheral (rtl/peripherals/pwm)

This directory contains the **portable PWM core and mode adapters** used throughout the system.
The design emphasizes determinism, safety, and reuse across motor control, LEDs, servos, and future multi-phase applications.

---

## Design philosophy (read this first)

This PWM implementation is **not** an MCU-style timer clone.

Key principles:
- Cycle-based timing (no fixed “bit width” PWM)
- Explicit timebase + compare separation
- True 0% and 100% duty support
- Glitch-free updates handled at the register layer (shadow + APPLY)
- Board-agnostic outputs (sign-magnitude, complementary, etc. handled by adapters)

Think of PWM here as a **time-domain DAC**, not a timer feature.

---

## File overview

### Core (portable, mode-agnostic)
These files form the **heart of the PWM system**.

- `pwm_timebase.sv`
  - Generates the PWM period counter (`cnt`)
  - Emits `period_end` pulse on wrap
  - Runtime-configurable period in clock cycles
  - Equivalent to a UART baud generator

- `pwm_compare.sv`
  - Generates raw PWM via `cnt < duty_cycles`
  - Clamps duty safely to period
  - Supports true 0% and 100% output

- `pwm_core_ip.sv`
  - Thin wrapper around timebase + compare
  - Applies default parameters (e.g. DEFAULT_PERIOD_CYCLES)
  - Exposes a stable interface for registers and adapters

These files **must not** include:
- bus logic
- register decoding
- board-specific pin mapping
- deadtime or complementary logic (added later)

---

## Modes and adapters (added incrementally)

Modes are implemented as **small adapter layers**, not baked into the core.

Planned / current modes:
- Sign-magnitude (PWM + DIR) — DC motors (L298, etc.)
- Complementary PWM — H-bridges / half-bridges
- Servo pulse mode — fixed frame, variable pulse width
- 3-phase PWM — phase-shifted outputs (SVPWM later)

Rule:
> The core generates *time*; adapters decide *meaning*.

---

## Configuration model

The PWM core operates on **active values**:
- `period_cycles`  (PWM period in clk cycles)
- `duty_cycles`    (on-time in clk cycles)

Higher layers (registers, FIFO, DMA) are responsible for:
- shadow registers
- atomic APPLY at `period_end`
- scaling from user units (%, µs, signed values)

The core intentionally does **no** scaling or unit conversion.

---

## Clocking and assumptions

- Single clock domain
- Designed for DE10-Lite default 50 MHz clock
- Typical DC motor PWM:
  - 4–20 kHz
  - Example: 10 kHz → `period_cycles = 5000`

Resolution is determined by:
```
resolution_bits ≈ log2(period_cycles)
```

---

## Safety rules (non-negotiable)

These invariants are enforced by design and must be preserved:

1. `duty_cycles = 0` → output always LOW
2. `duty_cycles >= period_cycles` → output always HIGH
3. `period_cycles < 2` is clamped internally
4. `enable = 0` forces output to safe state
5. No combinational feedback between outputs and timing logic

Deadtime, shoot-through prevention, and fault handling are added **after** compare logic.

---

## Testbench location

All PWM testbenches live in:
```
tb/unit/pwm/
```

Current tests cover:
- timebase wrap and `period_end` cadence
- duty edge cases (0%, mid, 100%)
- saturation behavior
- enable gating

No testbench code belongs in this directory.

---

## Common mistakes to avoid

- Do not hard-code PWM “bit widths”
- Do not mix deadtime into the timebase
- Do not add board-specific pin logic here
- Do not update period/duty mid-cycle without APPLY logic
- Do not assume MCU timer semantics

---

## Related documentation

- Engineering notebook:
  - `docs/notebook/ENG_NOTEBOOK_PWM.md`
- Repo layout rules:
  - `REPO_LAYOUT.md`
- Bring-up procedures:
  - `docs/bringup/`

---

## When adding new files

Ask:
1. Is this synthesizable and PWM-related? → belongs here
2. Is it mode-specific? → put in a clearly named adapter file
3. Is it test or debug logic? → belongs in `tb/`, not here

If unsure, default to **keeping the core small and boring**.
