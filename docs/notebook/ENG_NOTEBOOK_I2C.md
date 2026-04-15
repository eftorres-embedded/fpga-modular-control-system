# ENG NOTEBOOK - I2C


## Goal
Integrate an I2C master peripheral into the modular control system using the project's standard peripheral structure:

- vendor/core isolation
- local register file
- AXI4-Lite wrapper
- top-level subsystem integration
- Nios V software-driven testing

Primary near-term target device:
- MPU-6500 on the self-balancing kit

---

## Design Decision
Instead of continuing with the Intel Avalon I2C Host IP for this project branch, the design will pivot to an open-source Verilog I2C master core and keep the project-owned software-visible interface local to this repository.

Reasoning:

- the board-level electrical path was debugged and validated:
  - open-drain behavior worked
  - SDA/SCL pull-ups were added
  - manual line forcing and line readback behaved correctly
- the previous Avalon I2C Host path still reported a non-idle state before any transfer command was queued
- a custom register/MMIO layer fits this repository's architecture better and matches the SPI and PWM workstreams
- isolating the low-level bus engine from the software-visible interface keeps the project modular and makes future replacement easier

The project goal is not to claim authorship of the low-level protocol engine. The goal is to show clean SoC integration, register design, wrapper design, and system bring-up.

---

## Third-Party Core Credit
This I2C workstream is based on the open-source **verilog-i2c** project by **Alex Forencich**.

Planned source attribution approach:
- keep the original vendor RTL isolated in a dedicated vendor directory
- preserve original file names where practical
- keep project-owned wrapper/register logic outside the vendor tree
- document clearly which files are vendor-origin and which files are project-authored

Planned vendor isolation path:
`rtl/peripherals/i2c/vendor/verilog-i2c-master/`

Files that are *not* the preferred base for this repository's final peripheral contract:
- `i2c_master_axil.v`
- `i2c_master_wbs_8.v`
- `i2c_master_wbs_16.v`

Reason:
the project intends to maintain its own MMIO/register contract and AXI4-Lite wrapper so the peripheral matches the rest of the repository structure.

---

## Project-Owned Integration Strategy
Project-owned integration logic will remain separate from the vendor core.

Planned project-owned files:
- `rtl/peripherals/i2c/axi_lite_i2c.sv`
- `rtl/peripherals/i2c/regs/i2c_regs.sv`

This separation is intentional to:

- preserve attribution and licensing clarity
- avoid mixing vendor code with project code
- make future core replacement easier
- keep the software-visible contract under project control

---

## Planned Integration Layers
1. Vendor I2C master core
2. Project-owned register/MMIO layer
3. Project-owned AXI4-Lite wrapper
4. Top-level subsystem integration
5. Software test through Nios V
6. MPU-6500 register-level bring-up

---

## Early System Debug Summary
Before moving to the new I2C path, the previous hardware path was debugged far enough to establish several useful facts:

### Verified board/path behavior
- SDA and SCL use open-drain style drive at top level
- external pull-ups were added to SDA and SCL
- AD0 was tied low for MPU-6500 address `0x68`
- manual forcing of SDA/SCL low from FPGA logic worked
- readback of SDA/SCL through the top-level path also worked
- Signal Tap visibility was established for:
  - `mpu_i2c_scl_drive_low`
  - `mpu_i2c_scl_i`
  - `mpu_i2c_sda_drive_low`
  - `mpu_i2c_sda_i`

### Key conclusion from previous debug
The external pad path and board wiring were not the main blocker. The remaining issue appeared to be inside the previous I2C core/integration/reset path rather than the basic electrical interface.

This is useful because it reduces uncertainty for the next implementation pass:
- top-level open-drain hookup style is already validated
- GPIO pin choice is already validated
- MPU-6500 target address choice is already validated

---

## Top-Level I2C Pad Convention
The top-level I2C hookup will continue using the already-debugged open-drain convention:

```systemverilog
assign GPIO[PIN_MPU_I2C_SCL] = mpu_i2c_scl_drive_low ? 1'b0 : 1'bz;
assign GPIO[PIN_MPU_I2C_SDA] = mpu_i2c_sda_drive_low ? 1'b0 : 1'bz;

assign mpu_i2c_scl_i = GPIO[PIN_MPU_I2C_SCL];
assign mpu_i2c_sda_i = GPIO[PIN_MPU_I2C_SDA];
```

Conceptually:

- `*_drive_low = 1` -> line driven low
- `*_drive_low = 0` -> line released
- `*_i` -> sampled line level

This convention is already aligned with the physical behavior seen during manual debug.

---

## Planned Software-Visible Register Direction
A final register map is still to be defined, but the intended style is consistent with other repository peripherals.

Candidate register set:

```text
0x00 CTRL
0x04 STATUS
0x08 CLK_DIV
0x0C SLAVE_ADDR
0x10 REG_ADDR
0x14 TX_DATA
0x18 RX_DATA
0x1C CMD
0x20 IRQ_EN
0x24 IRQ_STATUS
```

Initial intent:
- keep bring-up simple
- support single-byte register write
- support repeated-start register read
- add interrupt support only after baseline polling flow works cleanly

---

## Planned Bring-Up Strategy
The first functional goal is a minimal MPU-6500 smoke test, not feature completeness.

Recommended bring-up order:

1. confirm idle bus levels in software-visible status
2. issue a simple register read to `WHO_AM_I`
3. confirm response at slave address `0x68`
4. read `PWR_MGMT_1`
5. clear sleep mode
6. read back `PWR_MGMT_1`
7. add accel/gyro register reads

---

## Initial Tasks
- isolate vendor RTL in a dedicated I2C vendor directory
- review `i2c_master.v` interface and handshake behavior
- define software-visible register map
- define command sequencing for:
  - write transaction
  - repeated-start read transaction
- connect register layer to vendor core
- add status reporting
- create basic smoke test
- verify `WHO_AM_I` read from MPU-6500

---

## Notes
The first objective is functional bring-up, not feature completeness.

Advanced items such as:
- FIFOs
- interrupt refinements
- burst support
- generalized transaction queueing

can be added after baseline MPU-6500 communication works.

This notebook entry is mainly to establish:
- attribution to the original I2C vendor core
- project ownership boundaries
- the integration direction for the I2C workstream
- lessons already learned from the previous debug path

---

## Directory Structure
```text
rtl/
└── peripherals/
    └── i2c/
        ├── vendor/
        │   └── verilog-i2c-master/
        │       └── rtl
        |           └──i2c_master.v
        ├── regs/
        │   └── i2c_regs.sv
        ├── axi_lite_i2c.sv
        │  
        └── README.md (optional, later)

tb/
└── unit/
    └── i2c/
        └── <planned testbenches>
```

---

## Current Direction Summary
The I2C workstream will follow the same overall architectural philosophy as SPI:

- reusable vendor bus engine
- project-owned register contract
- project-owned AXI4-Lite wrapper
- explicit top-level integration
- software-driven bring-up from Nios V

The low-level protocol engine is vendor-origin.
The software-visible peripheral and SoC integration remain project-owned.
