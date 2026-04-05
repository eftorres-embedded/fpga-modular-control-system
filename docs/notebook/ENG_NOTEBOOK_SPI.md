# ENG NOTEBOOK - SPI

## Status
SPI is the next active peripheral workstream.

## Goal
Integrate an SPI peripheral into the modular control system using the project’s standard peripheral structure:
- vendor/core isolation
- local register file
- AXI4-Lite wrapper
- top-level subsystem integration

## Design Decision
Instead of writing the SPI protocol engine from scratch, this project uses an existing open-source Verilog SPI core as the low-level shift/timing engine.

Reasoning:
- reduces time spent re-deriving standard SPI timing logic
- allows focus on SoC integration and software-visible interface design
- keeps the reusable architecture of this repository consistent

## Third-Party Core Strategy
Vendor RTL is isolated under:
`rtl/peripherals/spi/vendor/opencores_verilog_spi/trunk/`

Project-owned integration logic remains separate:
- `rtl/peripherals/spi/axi_lite_spi.sv`
- `rtl/peripherals/spi/regs/spi_regs.sv`

This separation is intentional to:
- preserve attribution and licensing clarity
- avoid mixing vendor code with project code
- make future core replacement easier

## Planned Integration Layers
1. SPI vendor core
2. SPI register file
3. AXI4-Lite wrapper
4. System/top-level integration
5. Software test through Nios V

## Initial Tasks
- review vendor SPI handshake and timing assumptions
- define software-visible register map
- connect register layer to vendor core
- add status and interrupt strategy
- create basic smoke test

## Notes
The first objective is functional bring-up, not feature completeness.
Advanced items such as FIFOs, interrupts, and extended transaction support can be added after baseline integration works.

## April 4, 2026
Finished implementing the MMIO wrapper for the SPI module, it implemented the following memory mapped registers
```text
//Register map (32-bit words):
//  0x00    CTRL
//          bit 0   ENABLE          WR      Turn SPI module on
//          bit 1   START           W1P     Start transaction
//          bit 2   XFER_END        WR      Default:1 > Realease CS after transfer; 0 > CS stays low
//          bit 3   CLR_DONE        W1P     Clears the DONE flag from STATUS register
//          bit 4   CLR_RX_VALID    W1P     Clears the RX_VALID flag from  STATUS register
//
//  0X04    STATUS
//          bit 0   BUSY            RO      Transactions is in progress
//          bit 1   DONE            RO      Transaction has finished    (sticky)
//          bit 2   RX_VALID        RO      Data received is valide     (sticky)
//          bit 3   TX_READY        RO      SPI module can send another word
//          bit 4   ENABLED         RO      SPI module is on (enabled)
//          bit 5   CS_ACTIVE       RO      CS is asserted
//
//  0x08    TXDATA
//          bits[7:0] TX byte       WO
//
//  0x0C    RXDATA
//          bits[7:0] RX byte       RO
//
//  0x10    IRQ_EN
//          bit 0   DONE_IE         RW      interrupt enable for transfer done
//          bit 1   RX_VALID_IE     RW      interrupt enable for RX valid
//
//  0x14    IRQ_STATUS
//          bit 0   DONE_IP         RO/W1C  interrupt   pending for done
//          bit 1   RX_VALID_IP     RO/W1C  interrupt pending for rx valid
//
```

I decided to add interrupt capability so I don't have the NIOS V (or any other processor) polling and wasting processor cycles. 

The test bench has been generated with assistance from ChatGPT to speed up testing

## PowerShell commands to run the testbench
```powershell
New-Item -ItemType Directory -Force build\sim\work | Out-Null
New-Item -ItemType Directory -Force build\sim\logs | Out-Null
New-Item -ItemType Directory -Force build\sim\waves | Out-Null

vlib build\sim\work

vlog -work build\sim\work -sv `
    .\rtl\peripherals\spi\vendor\opencores_verilog_spi\trunk\clk_valid.v `
    .\rtl\peripherals\spi\vendor\opencores_verilog_spi\trunk\spi_master.v `
    .\rtl\peripherals\spi\regs\spi_regs.sv `
    .\tb\unit\spi\tb_spi_regs.sv

vsim -c -work build/sim/work tb_spi_regs -l build/sim/logs/tb_spi_regs.log -wlf build/sim/waves/tb_spi_regs.wlf -do "run -all; quit"
```

After all the test passed, I decided to take a look at the waveforms by running the following command to open the GUI:
```powershell
vsim -voptargs=+acc -work build/sim/work tb_spi_regs -wlf build/sim/waves/tb_spi_regs.wlf
```
and then, inside the GUI ran the following commands:
```tcl
add wave sim:/tb_spi_regs/clk
add wave sim:/tb_spi_regs/rst_n
add wave sim:/tb_spi_regs/req_valid
add wave sim:/tb_spi_regs/req_write
add wave sim:/tb_spi_regs/req_addr
add wave sim:/tb_spi_regs/req_wdata
add wave sim:/tb_spi_regs/rsp_valid
add wave sim:/tb_spi_regs/rsp_rdata
add wave sim:/tb_spi_regs/irq
add wave sim:/tb_spi_regs/spi_cs_n
add wave sim:/tb_spi_regs/spi_sclk
add wave sim:/tb_spi_regs/spi_mosi
add wave sim:/tb_spi_regs/dut/start_fire
add wave sim:/tb_spi_regs/dut/busy
add wave sim:/tb_spi_regs/dut/done
add wave sim:/tb_spi_regs/dut/rx_valid
run -all
```

## SPI Transfer Waveform

### SPI Register Block – Simulation Results (tb_spi_regs)

![SPI TB PASS](img/2026-04-04-tb_spi_regs_testbench_pass.png)

**Summary:**  
The SPI register subsystem successfully completed a full transaction using the MMIO interface, including control, data transfer, status reporting, and interrupt signaling.

---

### Execution Breakdown

- **Initial State**
  - `enabled=0`, `busy=0`, `tx_ready=1`
  - Peripheral is idle and ready for configuration

- **Transfer Initiation**
  - CPU writes `TXDATA = 0xA5`
  - CPU sets `ENABLE=1` and issues `START`
  - `CS` asserted (`cs_active=1`)
  - `busy=1` confirms transfer in progress

- **During Transfer**
  - `tx_ready=0` (core is busy)
  - `done=0`, `rx_valid=0` (no premature completion flags)

- **Completion**
  - Transfer completes after ~17 polling cycles
  - `done=1`, `rx_valid=1` asserted
  - Confirms proper end-of-transfer detection

- **Data Path Verification**
  - `RXDATA = 0xA5`
  - Matches transmitted value via loopback (`MOSI → MISO`)
  - Confirms correct SPI shift and capture behavior

- **Interrupt Behavior**
  - `IRQ_STATUS = 0x3`
    - `DONE_IP = 1`
    - `RX_VALID_IP = 1`
  - Interrupt asserted only when enabled and pending
  - Confirms correct IRQ gating and sticky pending logic

- **Clear Operations (W1C / W1P)**
  - Writing to `IRQ_STATUS` clears pending bits
  - Writing to CTRL with `CLR_DONE` and `CLR_RX_VALID` clears sticky flags
  - Final STATUS returns to:
    - `busy=0`, `done=0`, `rx_valid=0`, `enabled=0`

---

### Key Design Validations

- MMIO interface correctly handles read/write transactions
- Control logic safely gates configuration changes during active transfer
- TXDATA is decoupled from active transfer (no corruption mid-transaction)
- Sticky status flags (`DONE`, `RX_VALID`) behave as intended
- Interrupt system correctly separates:
  - enable (`IRQ_EN`)
  - pending (`IRQ_STATUS`)
- Level-sensitive IRQ prevents missed events

---

### Notes

- Simulation uses loopback configuration (`spi_mosi → spi_miso`)
- Transfer length = 8 bits (default SPI_DW)
- Polling-based completion used for simplicity (interrupt-driven flow also verified)

---

### Conclusion

The SPI peripheral is functionally verified at the register-transfer level and is ready for:
- AXI4-Lite integration
- Platform Designer system integration
- Nios V software-driven testing

### SPI Transfer Waveform (tb_spi_regs)

![SPI Waveform](img/2026-04-04-tb_spi_regs_waveform.png)

**Figure:** Single SPI transaction showing MMIO write → START → shift → DONE → idle.

---

### Transaction Walkthrough

1. **MMIO Write Phase**
   - `req_valid` pulses indicate register writes from the testbench
   - `req_addr` and `req_wdata` configure:
     - TXDATA = `0xA5`
     - CTRL (ENABLE + START)
   - Corresponding `rsp_valid` confirms successful register access

2. **Transfer Start**
   - `start_fire` pulses high (internal event)
   - `busy` transitions from `0 → 1`
   - `spi_cs_n` goes low → SPI device selected

3. **Clocking / Data Shift**
   - `spi_sclk` produces **8 clock pulses** (SPI_DW = 8)
   - `spi_mosi` shifts out `0xA5` (MSB-first)
   - `spi_cs_n` remains low for entire transfer window
   - `busy` stays high during active shifting

4. **Transfer Completion**
   - After final clock:
     - `busy` deasserts (`1 → 0`)
     - `done` asserts (sticky flag)
     - `rx_valid` asserts (data ready)

5. **Post-Transfer State**
   - `spi_cs_n` returns high → transaction ends
   - System returns to idle
   - `done` and `rx_valid` remain asserted until cleared by software

---

### Key Timing Observations

- `spi_cs_n` cleanly bounds the transaction
- `spi_sclk` activity is strictly contained within `busy=1`
- No premature assertion of `done` or `rx_valid`
- `busy` accurately tracks the active transfer window
- Exactly **8 SCLK cycles** confirm correct data width configuration

---

### Data Integrity

- Transmitted data: `0xA5`
- Loopback path (`MOSI → MISO`) ensures received data matches transmitted data
- Confirms correct:
  - bit ordering (MSB-first)
  - shift timing
  - sampling alignment

---

### Design Validation

This waveform verifies:

- Correct MMIO → hardware interaction
- Proper synchronization between control and datapath
- Deterministic transaction boundaries
- Clean separation of:
  - control (`start_fire`)
  - execution (`busy`, `spi_sclk`)
  - completion (`done`, `rx_valid`)

---

### Conclusion

The SPI subsystem demonstrates correct functional behavior at the signal level, validating both control logic and serial data transfer timing. The design is ready for system-level integration.