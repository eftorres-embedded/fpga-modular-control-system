//spi_regs.sv
// -----------------------------------------------------------------------------
// This module wraps the SPI core from:
// https://opencores.org/projects/spi_verilog_interface
// Licensed under LGPL
// -----------------------------------------------------------------------------
//
//CPU-facing MMIO restister block for a simple SPI master perifpheral
//Version 1 design goals:
// -Deterministic, one-byte-per-start behavior
// -Vendor SPI master treated as a black box
// -Sticky DONE and RX_VALID status bit
// -START / Clear bits are write-one pulse actions
// - AXI-Lite Wrapper talks to this block through a generic MMIO interface
//
//Register map (32-bit words):
//  0x00    CTRL
//          bit 0   ENABLE          WR
//          bit 1   START           W1P
//          bit 2   XFER_END        WR
//          bit 3   CLR_DONE        W1P
//          bit 4   CLR_RX_VALID    W1P
//
//  0X04    STATUS
//  