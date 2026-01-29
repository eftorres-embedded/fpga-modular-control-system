# Repo Layout Rules (Source of Truth)

This repo follows a simple ownership model: **each concept has exactly one home**.
If a file “could fit in two places,” pick the owner folder below and do not duplicate.

---

## Top-level ownership

### 1) `rtl/` — Synthesizable HDL only
**What goes here**
- SystemVerilog/VHDL that is intended to synthesize to FPGA
- Reusable IP blocks and top-level RTL

**What does NOT go here**
- Testbenches, models, stimulus files, simulation-only helpers

Suggested structure:
- `rtl/common/` shared primitives (sync, reset, FIFOs)
- `rtl/bus/` bus fabric and MMIO adapters
- `rtl/peripherals/<ip>/` (uart, pwm, gpio, etc.)
- `rtl/top/` top-level wrappers

---

### 2) `tb/` — Simulation sources only (the only home for testbenches)
**What goes here**
- Unit testbenches: `tb/unit/<ip>/tb_*.sv`
- Integration testbenches: `tb/integration/`
- Behavioral models/BFMs: `tb/models/`
- Test vectors: `tb/vectors/`

**What does NOT go here**
- Generated waveforms/logs
- Quartus/EDA tool outputs

---

### 3) `build/` — Generated outputs only (safe to delete)
**What goes here**
- Simulation outputs: VCD/WLF/FST, logs, compiled sim artifacts
- Reports (timing, utilization) if you choose to store them outside Quartus db

Suggested:
- `build/sim/waves/`
- `build/sim/logs/`
- `build/reports/`
- `build/artifacts/`

Rule: If it can be regenerated, it belongs in `build/` and should be gitignored where appropriate.

---

### 4) `docs/` — Human documentation
**`docs/architecture/`**
- block diagrams, interface specs, timing notes

**`docs/notebook/`**
- engineering lab notebook(s): narrative, decisions, experiments
- images for notebook entries: `docs/notebook/img/`

**`docs/bringup/`**
- repeatable runbooks: wiring, power-up, scope procedures, “known-good” steps
- meant to be followed like a checklist

Rule: notebook = “what happened & why”; bringup = “how to reproduce safely”.

---

### 5) Tooling and other
- `quartus/` Quartus project files and tool DB outputs
- `constraints/` SDC and timing constraints
- `ip/` generated and third-party IP
- `sw/` firmware/host utilities/protocol code

---

## Anti-maze rules
1) Testbenches go in `tb/` only.
2) Generated outputs go in `build/` only.
3) Documentation lives in `docs/` only.
4) If two folders mean the same thing, pick one owner and stop using the other.
5) Do not mix generated outputs with sources.

---
