# Engineering Lab Notebook - PWM Subsystem (DE10-Lite, 50MHz)

**Owner:** Eder Torres
**Repo:** https://github.com/eftorres-embedded/fpga-modular-control-system
**Clock:** 50 MHz (DE10-Lite)
**Scope:** pwm_timebase, pwm_compare, pwm_core, later regs + modes + adpaters

---

## 01-29-2026 - PWM Core Bring-up (timebase + compare)

### Objective
- Implement portable PWM core:
    -   `pwm_timebase.sv` (up-counter + period_end-pulse + period_start_pulse)
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


## Procedure
- [ ] add RTL files:
  -`rtl/peripherals/pwm/pwm_timebase.sv`
  -`rtl/perifpherals/pwm/pwm_compare.sv`
  -`rtl/peripherals/pwm/pwm_core_ip.sv`

- [ ] Add testbench:
  - `tb/unit/pwm/tb_pwm_core_ip.sv`

- [ ] Write the code:
  - [x] `pwm_timebase`
  - [ ] `pwm_compare.sv`
  - [ ] `pwm_core_ip.sv`

- [ ] Write the testbench:
  - [ ] `tb_pwm_core_ip`

- [ ] Run simulation (Questa Altera)
  - [x] Create work library under `build/sim/work`
  - [ ] Compile RTL + TB
  - [ ] Run TB in command-line mode
  - [ ] Save transcript to `build/sim/logs/tb_pwm_core_ip.txt`
  - [ ] Dump waveform to `build/simwaves/tb_pwm_core_ip.wlf`

- [ ] Open waveform:
  - [ ] Inspect `cnt`, `period_end`, `period_cycles`, `duty_cycles`, `pwm_raw`
  - [ ] Screenshot: `docs/notebook/img/date_pwm_core10khz_50pct.png`

### Test Plan (core)
- [ ] T1 Reset: `cnt=0`, `pwm_raw=0`
- [ ] T2 Period: `period_end` every 5000 cycles
- [ ] T3 Duty extremes:
  - [ ] `duty=0` always low
  - [ ] `duty=2500` exactly 2500 high per period
  - [ ] `duty=5000` always high
- [ ] T4 Saturation: `duty=6000` behaves like 100%

### Results
| Test | Expected | Observed | Pass/Fail | Notes|
|---|---|---|---|
| T1 | - | - | - |
| T2 | - | - | - |
| T3a | - | - | - |
| T3b | - | - | - |
| T3c | - | - | - |

### Evidence (wvaeforms / screenshots)
- Waveform capture: `docs/notebook/img/file.png`
- VCD file: `sim/out/tb_pwm_cre.vcd`

### Issues / Debug Notes
- None today

### Next Steps
- [ ] Add randomized tst for (perio, duty) pairs
- [ ] Decid if `period_start` is need by higher layers
- [ ] Start `pwm_regs.sv` with shadow+APPLY