# Repository Layout

```text
fpga-modular-control-system/
├── rtl/
├── pd/
├── quartus/
├── constraints/
├── tb/
├── sw/
├── docs/
├── ip/
└── licenses/
```

## Directory map

| Path | Contents |
|---|---|
| `rtl/common/` | shared utility blocks |
| `rtl/peripherals/` | reusable peripheral IP |
| `rtl/platform/` | board-specific wrappers |
| `rtl/top/` | top-level integration |
| `pd/` | `.qsys`, `.sopcinfo`, `_hw.tcl`, generated PD output |
| `quartus/project/` | `.qpf`, `.qsf`, `.stp`, Quartus output |
| `constraints/quartus/` | `.sdc` files |
| `tb/unit/` | unit testbenches |
| `tb/integration/` | integration testbenches |
| `sw/app/` | Nios V application |
| `sw/drivers/` | C drivers |
| `docs/architecture/` | interface/design notes |
| `docs/bringup/` | procedures and checklists |
| `docs/notebook/` | dated engineering notes |
