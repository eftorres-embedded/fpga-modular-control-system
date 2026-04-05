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

vsim -c -work build\sim\work tb_spi_regs `
    -l build\sim\logs\tb_spi_regs.log `
    -wlf build\sim\waves\tb_spi_regs.wlf `
    -do "run -all; quit"
```