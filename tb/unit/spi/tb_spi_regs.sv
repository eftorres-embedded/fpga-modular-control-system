`timescale 1ns/1ps
// Testbench scaffold generated with assistance from ChatGPT (OpenAI)
// Modified and validated by Eder Torres
// -----------------------------------------------------------------------------
// tb_spi_regs.sv
// -----------------------------------------------------------------------------
// Simple learning-oriented testbench for spi_regs.sv.
//
// Goals:
//   1. Keep the testbench readable.
//   2. Exercise the software-visible behavior of the register block.
//   3. Use a very simple SPI environment: loop MOSI back into MISO.
//   4. Let you re-run the same TB with different CPOL / CPHA / BITORDER / CLKDIV.
//
// What this testbench checks:
//   - Reset defaults
//   - Single-byte transfer
//   - Two-byte transfer
//   - Four-byte transfer
//   - CTRL writes while BUSY=1
//   - CTRL writes while XFER_OPEN=1
//   - Sticky DONE / RX_VALID behavior
//   - IRQ pending behavior
//
// Important simplification:
//   We do NOT build a full external SPI slave model here.
//   Instead, we use:
//       assign spi_miso = spi_mosi;
//   so received data should match transmitted data.
// -----------------------------------------------------------------------------


module tb_spi_regs;

    // -------------------------------------------------------------------------
    // Change these four values to test a different SPI configuration.
    // Re-run the same testbench for the other modes / bit order / divider.
    // -------------------------------------------------------------------------
    localparam bit    CPOL_TB     = 1'b1;
    localparam bit    CPHA_TB     = 1'b1;
    localparam string BITORDER_TB = "LSB_FIRST";
    localparam int    CLKDIV_TB   = 8;

    // -------------------------------------------------------------------------
    // Local copies of register offsets and bit positions.
    // This keeps the testbench easy to read.
    // -------------------------------------------------------------------------
    localparam int ADDR_W = 12;
    localparam int DATA_W = 32;
    localparam int SPI_DW = 8;

    localparam logic [ADDR_W-1:0] REG_CTRL       = 'h0;
    localparam logic [ADDR_W-1:0] REG_STATUS     = 'h4;
    localparam logic [ADDR_W-1:0] REG_TXDATA     = 'h8;
    localparam logic [ADDR_W-1:0] REG_RXDATA     = 'hC;
    localparam logic [ADDR_W-1:0] REG_IRQ_EN     = 'h10;
    localparam logic [ADDR_W-1:0] REG_IRQ_STATUS = 'h14;

    localparam int CTRL_ENABLE_BIT       = 0;
    localparam int CTRL_START_BIT        = 1;
    localparam int CTRL_XFER_END_BIT     = 2;
    localparam int CTRL_CLR_DONE_BIT     = 3;
    localparam int CTRL_CLR_RX_VALID_BIT = 4;

    localparam int STATUS_BUSY_BIT       = 0;
    localparam int STATUS_DONE_BIT       = 1;
    localparam int STATUS_RX_VALID_BIT   = 2;
    localparam int STATUS_TX_READY_BIT   = 3;
    localparam int STATUS_ENABLED_BIT    = 4;
    localparam int STATUS_CS_ACTIVE_BIT  = 5;
    localparam int STATUS_XFER_OPEN_BIT  = 6;

    localparam int IRQ_DONE_BIT          = 0;
    localparam int IRQ_RX_VALID_BIT      = 1;

    // -------------------------------------------------------------------------
    // DUT interface signals
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    logic                  req_valid;
    logic                  req_ready;
    logic                  req_write;
    logic [ADDR_W-1:0]     req_addr;
    logic [DATA_W-1:0]     req_wdata;
    logic [(DATA_W/8)-1:0] req_wstrb;

    logic                  rsp_valid;
    logic                  rsp_ready;
    logic [DATA_W-1:0]     rsp_rdata;
    logic                  rsp_err;

    logic irq;

    logic spi_sclk;
    logic spi_mosi;
    logic spi_miso;
    logic spi_cs_n;

    int errors;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    spi_regs #(
        .ADDR_W   (ADDR_W),
        .DATA_W   (DATA_W),
        .CPOL     (CPOL_TB),
        .CPHA     (CPHA_TB),
        .BITORDER (BITORDER_TB),
        .SPI_DW   (SPI_DW),
        .CLKDIV   (CLKDIV_TB)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .req_valid (req_valid),
        .req_ready (req_ready),
        .req_write (req_write),
        .req_addr  (req_addr),
        .req_wdata (req_wdata),
        .req_wstrb (req_wstrb),
        .rsp_valid (rsp_valid),
        .rsp_ready (rsp_ready),
        .rsp_rdata (rsp_rdata),
        .rsp_err   (rsp_err),
        .irq       (irq),
        .spi_sclk  (spi_sclk),
        .spi_mosi  (spi_mosi),
        .spi_miso  (spi_miso),
        .spi_cs_n  (spi_cs_n)
    );

    // -------------------------------------------------------------------------
    // Simple 100 MHz clock
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Simple loopback model:
    // returned SPI data equals transmitted SPI data.
    // -------------------------------------------------------------------------
    assign spi_miso = spi_mosi;

    // -------------------------------------------------------------------------
    // Always ready to accept a response from spi_regs.
    // -------------------------------------------------------------------------
    initial begin
        rsp_ready = 1'b1;
    end

    // -------------------------------------------------------------------------
    // Small helpers for pass/fail reporting.
    // -------------------------------------------------------------------------
    task automatic fail(input string msg);
        begin
            errors = errors + 1;
            $display("[%0t] ERROR: %s", $time, msg);
        end
    endtask

    task automatic check(input bit cond, input string msg);
        begin
            if (!cond)
                fail(msg);
        end
    endtask

    // -------------------------------------------------------------------------
    // Build a CTRL register word for MMIO writes.
    // -------------------------------------------------------------------------
    function automatic [31:0] ctrl_word(
        input bit enable,
        input bit start,
        input bit xfer_end,
        input bit clr_done,
        input bit clr_rx_valid
    );
        ctrl_word = '0;
        ctrl_word[CTRL_ENABLE_BIT]       = enable;
        ctrl_word[CTRL_START_BIT]        = start;
        ctrl_word[CTRL_XFER_END_BIT]     = xfer_end;
        ctrl_word[CTRL_CLR_DONE_BIT]     = clr_done;
        ctrl_word[CTRL_CLR_RX_VALID_BIT] = clr_rx_valid;
    endfunction

    // -------------------------------------------------------------------------
    // MMIO write:
    // send one write request and wait for one response.
    // -------------------------------------------------------------------------
    task automatic mmio_write(
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] data,
        input logic [(DATA_W/8)-1:0] strb = '1
    );
        begin
            @(posedge clk);
            while (!req_ready) @(posedge clk);

            req_valid <= 1'b1;
            req_write <= 1'b1;
            req_addr  <= addr;
            req_wdata <= data;
            req_wstrb <= strb;

            @(posedge clk);
            req_valid <= 1'b0;
            req_write <= 1'b0;
            req_addr  <= '0;
            req_wdata <= '0;
            req_wstrb <= '0;

            wait (rsp_valid === 1'b1);
            check(!rsp_err, $sformatf("write to 0x%0h returned rsp_err", addr));
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // MMIO read:
    // send one read request and wait for one response.
    // -------------------------------------------------------------------------
    task automatic mmio_read(
        input  logic [ADDR_W-1:0] addr,
        output logic [DATA_W-1:0] data
    );
        begin
            @(posedge clk);
            while (!req_ready) @(posedge clk);

            req_valid <= 1'b1;
            req_write <= 1'b0;
            req_addr  <= addr;
            req_wdata <= '0;
            req_wstrb <= '0;

            @(posedge clk);
            req_valid <= 1'b0;
            req_addr  <= '0;

            wait (rsp_valid === 1'b1);
            check(!rsp_err, $sformatf("read from 0x%0h returned rsp_err", addr));
            data = rsp_rdata;
            @(posedge clk);
        end
    endtask

    task automatic read_status(output logic [31:0] status);
        mmio_read(REG_STATUS, status);
    endtask

    // -------------------------------------------------------------------------
    // Wait helpers
    // -------------------------------------------------------------------------
    task automatic wait_busy_state(input bit expected, input int max_cycles = 1000);
        int i;
        begin
            for (i = 0; i < max_cycles; i++) begin
                if (dut.busy === expected)
                    return;
                @(posedge clk);
            end
            fail($sformatf("timeout waiting for busy=%0b", expected));
        end
    endtask

    task automatic wait_xfer_open_state(input bit expected, input int max_cycles = 1000);
        int i;
        begin
            for (i = 0; i < max_cycles; i++) begin
                if (dut.xfer_open === expected)
                    return;
                @(posedge clk);
            end
            fail($sformatf("timeout waiting for xfer_open=%0b", expected));
        end
    endtask

    // -------------------------------------------------------------------------
    // Wait until the SPI engine is ready for the next byte.
    //
    // In this design, START is only accepted when:
    //   - BUSY = 0
    //   - vendor core ready = 1
    //
    // So for byte 2 / byte 3 / byte 4 of an open transaction, the TB should
    // wait here before pulsing START again.
    // -------------------------------------------------------------------------
    task automatic wait_tx_ready(input int max_cycles = 2000);
        int i;
        begin
            for (i = 0; i < max_cycles; i++) begin
                if ((dut.busy === 1'b0) && (dut.core_wready === 1'b1))
                    return;
                @(posedge clk);
            end
            fail("timeout waiting for TX_READY");
        end
    endtask

    // -------------------------------------------------------------------------
    // Clear sticky STATUS flags.
    // -------------------------------------------------------------------------
    task automatic clear_status_flags;
        begin
            mmio_write(REG_CTRL,
                       ctrl_word(dut.ctrl_enable, 1'b0, dut.ctrl_xfer_end, 1'b1, 1'b1));
        end
    endtask

    // -------------------------------------------------------------------------
    // Clear pending IRQ bits.
    // -------------------------------------------------------------------------
    task automatic clear_irq_pending(input bit clr_done, input bit clr_rx_valid);
        logic [31:0] w;
        begin
            w = '0;
            w[IRQ_DONE_BIT]     = clr_done;
            w[IRQ_RX_VALID_BIT] = clr_rx_valid;
            mmio_write(REG_IRQ_STATUS, w);
        end
    endtask

    // -------------------------------------------------------------------------
    // Reset sequence
    // -------------------------------------------------------------------------
    task automatic reset_dut;
        begin
            req_valid = 1'b0;
            req_write = 1'b0;
            req_addr  = '0;
            req_wdata = '0;
            req_wstrb = '0;

            errors = 0;

            rst_n = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (5) @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Test 1: reset defaults
    // -------------------------------------------------------------------------
    task automatic test_reset_defaults;
        logic [31:0] ctrl_reg;
        logic [31:0] status;
        logic [31:0] irq_en;
        logic [31:0] irq_st;
        begin
            $display("Running test_reset_defaults...");

            mmio_read(REG_CTRL, ctrl_reg);
            check(ctrl_reg[CTRL_ENABLE_BIT]   == 1'b0, "reset: CTRL.ENABLE should be 0");
            check(ctrl_reg[CTRL_XFER_END_BIT] == 1'b1, "reset: CTRL.XFER_END should be 1");

            mmio_read(REG_STATUS, status);
            check(status[STATUS_BUSY_BIT]      == 1'b0, "reset: BUSY should be 0");
            check(status[STATUS_DONE_BIT]      == 1'b0, "reset: DONE should be 0");
            check(status[STATUS_RX_VALID_BIT]  == 1'b0, "reset: RX_VALID should be 0");
            check(status[STATUS_TX_READY_BIT]  == 1'b1, "reset: TX_READY should be 1");
            check(status[STATUS_ENABLED_BIT]   == 1'b0, "reset: ENABLED should be 0");
            check(status[STATUS_CS_ACTIVE_BIT] == 1'b0, "reset: CS_ACTIVE should be 0");
            check(status[STATUS_XFER_OPEN_BIT] == 1'b0, "reset: XFER_OPEN should be 0");

            mmio_read(REG_IRQ_EN, irq_en);
            check(irq_en[IRQ_DONE_BIT]     == 1'b0, "reset: DONE_IE should be 0");
            check(irq_en[IRQ_RX_VALID_BIT] == 1'b0, "reset: RX_VALID_IE should be 0");

            mmio_read(REG_IRQ_STATUS, irq_st);
            check(irq_st[IRQ_DONE_BIT]     == 1'b0, "reset: DONE_IP should be 0");
            check(irq_st[IRQ_RX_VALID_BIT] == 1'b0, "reset: RX_VALID_IP should be 0");
        end
    endtask

    // -------------------------------------------------------------------------
    // Test 2: single-byte transfer
    //
    // Loopback means RXDATA should match TXDATA.
    // -------------------------------------------------------------------------
    task automatic test_single_byte;
        logic [31:0] status;
        logic [31:0] rxdata;
        begin
            $display("Running test_single_byte...");

            // Enable SPI, mark this byte as final.
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b0, 1'b1, 1'b0, 1'b0));
            mmio_write(REG_TXDATA, 32'h0000003C);
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b1, 1'b1, 1'b0, 1'b0));

            wait_busy_state(1'b1);
            wait_busy_state(1'b0);
            wait_xfer_open_state(1'b0);

            read_status(status);
            check(status[STATUS_DONE_BIT]      == 1'b1, "single-byte: DONE should be 1");
            check(status[STATUS_RX_VALID_BIT]  == 1'b1, "single-byte: RX_VALID should be 1");
            check(status[STATUS_BUSY_BIT]      == 1'b0, "single-byte: BUSY should be 0");
            check(status[STATUS_XFER_OPEN_BIT] == 1'b0, "single-byte: XFER_OPEN should be 0");

            mmio_read(REG_RXDATA, rxdata);
            check(rxdata[7:0] == 8'h3C,
                  $sformatf("single-byte: expected RXDATA=0x3C, got 0x%02x", rxdata[7:0]));

            clear_status_flags();
        end
    endtask

    // -------------------------------------------------------------------------
    // Test 3: two-byte transaction
    //
    // Things checked here:
    //   - first byte is launched as non-final
    //   - second byte is launched as final
    //   - ENABLE writes are ignored while XFER_OPEN=1
    //   - XFER_END can be updated for the next byte
    //   - IRQ pending behavior
    // -------------------------------------------------------------------------
    task automatic test_two_byte_transaction;
        logic [31:0] ctrl_reg;
        logic [31:0] status;
        logic [31:0] rxdata;
        logic [31:0] irq_st;
        begin
            $display("Running test_two_byte_transaction...");

            mmio_write(REG_IRQ_EN, 32'h00000003);
            clear_irq_pending(1'b1, 1'b1);
            clear_status_flags();

            // Byte 0: non-final
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b0, 1'b0, 1'b0, 1'b0));
            mmio_write(REG_TXDATA, 32'h000000A1);
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b1, 1'b0, 1'b0, 1'b0));

            // Wait until the first byte is in flight.
            wait (dut.busy && dut.xfer_open);

            // While BUSY=1 and XFER_OPEN=1:
            //   - ENABLE write should be ignored
            //   - XFER_END write should update the NEXT byte's launch setting
            mmio_write(REG_CTRL,   ctrl_word(1'b0, 1'b0, 1'b1, 1'b0, 1'b0));
            mmio_write(REG_TXDATA, 32'h000000B2);

            // First byte completes, transaction stays open.
            wait_busy_state(1'b0);
            wait_xfer_open_state(1'b1);

            mmio_read(REG_CTRL, ctrl_reg);
            check(ctrl_reg[CTRL_ENABLE_BIT]   == 1'b1,
                  "two-byte: ENABLE changed during open transaction");
            check(ctrl_reg[CTRL_XFER_END_BIT] == 1'b1,
                  "two-byte: XFER_END should be updated for next byte");

            read_status(status);
            check(status[STATUS_DONE_BIT]      == 1'b0,
                  "two-byte after byte0: DONE should be 0");
            check(status[STATUS_RX_VALID_BIT]  == 1'b1,
                  "two-byte after byte0: RX_VALID should be 1");
            check(status[STATUS_XFER_OPEN_BIT] == 1'b1,
                  "two-byte after byte0: XFER_OPEN should still be 1");

            mmio_read(REG_RXDATA, rxdata);
            check(rxdata[7:0] == 8'hA1,
                  $sformatf("two-byte first RX: expected 0xA1, got 0x%02x", rxdata[7:0]));

            mmio_read(REG_IRQ_STATUS, irq_st);
            check(irq_st[IRQ_RX_VALID_BIT] == 1'b1,
                  "two-byte after byte0: RX_VALID_IP should be 1");
            check(irq_st[IRQ_DONE_BIT]     == 1'b0,
                  "two-byte after byte0: DONE_IP should be 0");

            clear_irq_pending(1'b0, 1'b1);
            clear_status_flags();

            // Between bytes, XFER_OPEN is still 1, so ENABLE must still be protected.
            mmio_write(REG_CTRL, ctrl_word(1'b0, 1'b0, 1'b1, 1'b0, 1'b0));
            mmio_read(REG_CTRL, ctrl_reg);
            check(ctrl_reg[CTRL_ENABLE_BIT] == 1'b1,
                  "two-byte between bytes: ENABLE changed while XFER_OPEN=1");

            // Final byte:
            // Wait for TX_READY before pulsing START again.
            wait_tx_ready();
            mmio_write(REG_CTRL, ctrl_word(1'b1, 1'b1, 1'b1, 1'b0, 1'b0));

            wait_busy_state(1'b1);
            wait_busy_state(1'b0);
            wait_xfer_open_state(1'b0);

            read_status(status);
            check(status[STATUS_DONE_BIT]      == 1'b1,
                  "two-byte final: DONE should be 1");
            check(status[STATUS_RX_VALID_BIT]  == 1'b1,
                  "two-byte final: RX_VALID should be 1");
            check(status[STATUS_XFER_OPEN_BIT] == 1'b0,
                  "two-byte final: XFER_OPEN should be 0");

            mmio_read(REG_RXDATA, rxdata);
            check(rxdata[7:0] == 8'hB2,
                  $sformatf("two-byte final RX: expected 0xB2, got 0x%02x", rxdata[7:0]));

            mmio_read(REG_IRQ_STATUS, irq_st);
            check(irq_st[IRQ_RX_VALID_BIT] == 1'b1,
                  "two-byte final: RX_VALID_IP should be 1");
            check(irq_st[IRQ_DONE_BIT]     == 1'b1,
                  "two-byte final: DONE_IP should be 1");

            clear_irq_pending(1'b1, 1'b1);
            clear_status_flags();
        end
    endtask

    // -------------------------------------------------------------------------
    // Test 4: four-byte transaction
    //
    // This checks:
    //   - transaction stays open across multiple bytes
    //   - START while BUSY=1 is ignored
    //   - later bytes require waiting for TX_READY before START
    // -------------------------------------------------------------------------
    task automatic test_four_byte_transaction;
        logic [31:0] status;
        logic [31:0] rxdata;
        begin
            $display("Running test_four_byte_transaction...");

            clear_irq_pending(1'b1, 1'b1);
            clear_status_flags();

            // -----------------------------------------------------------------
            // Byte 0: non-final
            // -----------------------------------------------------------------
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b0, 1'b0, 1'b0, 1'b0));
            mmio_write(REG_TXDATA, 32'h00000010);
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b1, 1'b0, 1'b0, 1'b0));

            wait_busy_state(1'b1);

            // Try to issue another START while BUSY=1.
            // This should be ignored by the DUT.
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b1, 1'b0, 1'b0, 1'b0));

            wait_busy_state(1'b0);
            wait_xfer_open_state(1'b1);

            // -----------------------------------------------------------------
            // Byte 1: non-final
            // -----------------------------------------------------------------
            mmio_write(REG_TXDATA, 32'h00000020);
            wait_tx_ready();
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b1, 1'b0, 1'b0, 1'b0));

            wait_busy_state(1'b1);
            wait_busy_state(1'b0);
            wait_xfer_open_state(1'b1);

            // -----------------------------------------------------------------
            // Byte 2: non-final
            // -----------------------------------------------------------------
            mmio_write(REG_TXDATA, 32'h00000030);
            wait_tx_ready();
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b1, 1'b0, 1'b0, 1'b0));

            wait_busy_state(1'b1);
            wait_busy_state(1'b0);
            wait_xfer_open_state(1'b1);

            // -----------------------------------------------------------------
            // Byte 3: final
            // -----------------------------------------------------------------
            mmio_write(REG_TXDATA, 32'h00000040);
            wait_tx_ready();
            mmio_write(REG_CTRL,   ctrl_word(1'b1, 1'b1, 1'b1, 1'b0, 1'b0));

            wait_busy_state(1'b1);
            wait_busy_state(1'b0);
            wait_xfer_open_state(1'b0);

            read_status(status);
            check(status[STATUS_DONE_BIT]      == 1'b1,
                  "four-byte final: DONE should be 1");
            check(status[STATUS_XFER_OPEN_BIT] == 1'b0,
                  "four-byte final: XFER_OPEN should be 0");

            mmio_read(REG_RXDATA, rxdata);
            check(rxdata[7:0] == 8'h40,
                  $sformatf("four-byte final RX: expected 0x40, got 0x%02x", rxdata[7:0]));

            clear_irq_pending(1'b1, 1'b1);
            clear_status_flags();
        end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display("tb_spi_regs starting");
        $display("  CPOL     = %0d", CPOL_TB);
        $display("  CPHA     = %0d", CPHA_TB);
        $display("  BITORDER = %s", BITORDER_TB);
        $display("  CLKDIV   = %0d", CLKDIV_TB);
        $display("============================================================");

        reset_dut();

        test_reset_defaults();
        test_single_byte();
        test_two_byte_transaction();
        test_four_byte_transaction();

        if (errors == 0) begin
            $display("TB PASS");
        end else begin
            $fatal(1, "TB FAIL: %0d error(s)", errors);
        end

        $finish;
    end

    // -------------------------------------------------------------------------
    // Global timeout
    // -------------------------------------------------------------------------
    initial begin
        #2_000_000;
        $fatal(1, "Timeout in tb_spi_regs");
    end

endmodule