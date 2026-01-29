# Engineering Lab Notebook - PWM Subsystem (DE10-Lite, 50MHz)

**Owner:** Eder Torres
**Repo:** https://github.com/eftorres-embedded/fpga-modular-control-system
**Clock:** 50 MHz (DE10-Lite)
**Scope:** pwm_timebase, pwm_compare, pwm_core, later regs + modes + adpaters

---

## 01-29-2026 - PWM Core Bring-up (timebase + compare)

### Objective
- Implement portable PWM core:
    -   `pwm_timebase.sv` (counter + period_end)
    -   `pwm_compare.sv` (cnt<duty)
    -   `pwm_core.sv` wrapper (defaults + clamping policy)
- Create minimal testbench  `tb_pwm_core.sv`:
  1) verify `period_end` spacing
  2) verify duty counts (0%, 50%, 100%)

  ### Requirements / Constraints
  - `clk = 50_000_000` Hz
  - Start with `f_pwm = 10` KHz => `period_cycles = 5000` (one PWM period must last 5,000 clock cycles)
  - Duty must support true 0% and 100%
  - Clamp `period_cycles < 2` to 2: this is to avoid edgecases such `period_cycles == 0`, when comparing, the comparison might become  `period_cycles - 1` which will return `0xFFFF...FF`. Or, if `period_cycles == 1`, when comparing the `cnt`, it will be something like if (`cnt < duty` becomes meaning les, `period_end` will fire every cycle.
  - Clamp `duty_cycles > period_cycles` to period

  ### Design Decisions
  | Decision | Choice | Rationale |
  |---|---:|---|
  | Counter width | 32 bits | Cheap, avoids future limits |
  | Disable bahvior | force `cnt=0`, `pwm_raw=0` | Safe for motors; deterministic|
  | Period update | immedate (core); boundary-sync later | Keep core portable; Apply hande in regs layer |
