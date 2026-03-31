# Repository Layout

This repository is organized to separate reusable RTL, platform-specific integration, software, and documentation.

The goal is to keep **source-of-truth files clean, modular, and portable**, while isolating tool-generated outputs.

---

## Top-Level Structure

```text
fpga-modular-control-system/
├── rtl/           # reusable RTL (vendor-agnostic)
├── pd/            # Platform Designer systems (source-of-truth)
├── quartus/       # Quartus project files (Intel-specific)
├── constraints/   # timing and pin constraints
├── tb/            # simulation testbenches
├── sw/            # Nios V software (app + BSP)
├── docs/          # architecture, bring-up, notebooks
├── ip/            # packaged / reusable IP (optional)
└── licenses/      # third-party licenses
```

---

## RTL Organization

```text
rtl/
├── common/        # reusable utility modules
├── peripherals/   # modular peripherals
│   ├── pwm/
│   ├── spi/
│   ├── uart/
│   └── lcd/
└── top/           # top-level integration modules
```

### Design Rules

* `common/` contains reusable, vendor-agnostic building blocks
* `peripherals/` are self-contained subsystems
* each peripheral owns:

  * its core logic
  * its register interface
  * its AXI4-Lite wrapper (if applicable)
* **no global `bus/` folder**

  * bus wrappers live inside each peripheral

---

## Peripheral Structure

Each peripheral follows a consistent internal layout:

```text
peripheral/
├── core/          # datapath / protocol logic
├── regs/          # MMIO register layer
├── axi_lite_*.sv  # bus interface
├── *_subsystem.sv # integration glue
└── README.md
```

Vendor IP (if used) is isolated:

```text
spi/
└── vendor/
    └── opencores_verilog_spi/
```

---

## Platform Designer (pd/)

```text
pd/
├── *.qsys         # system definition (source-of-truth)
├── *.sopcinfo     # hardware description for software tools
└── <system_name>/
    ├── synthesis/     # generated HDL (ignored)
    ├── submodules/    # generated IP (ignored)
    └── simulation/    # generated simulation files (ignored)
```

### Notes

* `.qsys` and `.sopcinfo` are **tracked**
* generated folders (`synthesis/`, `submodules/`) are **not source-of-truth**
* this directory represents the **CPU + interconnect + peripheral system**

---

## Software (sw/)

```text
sw/
├── app/           # Nios V application
│   ├── src/
│   └── build/     # generated (ignored)
└── bsp/           # Board Support Package
```

### Notes

* `app/` contains test programs and peripheral control logic
* `bsp/` is tied to the Platform Designer system
* build outputs are generated via CMake and not tracked
* software validates hardware through MMIO

---

## Quartus (quartus/)

```text
quartus/
└── project/
    ├── *.qpf
    ├── *.qsf
    ├── db/              # generated (ignored)
    ├── incremental_db/  # generated (ignored)
    └── output_files/    # generated (ignored)
```

### Notes

* `.qpf` and `.qsf` are source-of-truth
* all compilation outputs are tool-generated and should not be tracked

---

## Constraints

```text
constraints/
└── quartus/
    └── *.sdc
```

Defines:

* clock timing
* I/O timing
* board-level constraints

---

## Testbenches (tb/)

```text
tb/
├── unit/          # module-level tests
└── integration/   # system-level tests
```

Focus:

* functional validation of RTL modules
* waveform-based debugging

---

## Documentation (docs/)

```text
docs/
├── architecture/
├── bringup/
└── notebook/
```

* `architecture/` → design descriptions and diagrams
* `bringup/` → hardware validation procedures
* `notebook/` → engineering logs and experiments

---

## Design Philosophy

This repository follows a layered system approach:

```text
RTL (vendor-agnostic)
        ↓
Platform Integration (pd/)
        ↓
Software Control (sw/)
        ↓
Hardware Validation
```

Key principles:

* isolate vendor-specific tooling
* keep RTL reusable and portable
* define clear software-hardware contracts
* separate source from generated artifacts
