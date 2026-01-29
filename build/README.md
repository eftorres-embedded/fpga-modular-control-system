# build/

Generated artifacts only.

This directory contains **outputs produced by tools**, not source files.

## What goes here
- Simulation outputs (VCD/WLF/FST)
- Simulation logs
- Synthesis / timing reports
- Packaged build artifacts

## Suggested structure
- build/sim/waves/
- build/sim/logs/
- build/reports/
- build/artifacts/

## Rules
- Safe to delete at any time
- Should generally be gitignored
- Never put hand-written source files here
