`timescale 1ns/1ps

module tb_i2c_regs;

    localparam int ADDR_W     = 12;
    localparam int DATA_W     = 32;
    localparam int BYTE_W     = 8;
    localparam int CMD_W      = 3;
    localparam int DIVISOR_W  = 16;

    localparam logic [ADDR_W-1:0] REG_STATUS  = 12'h000;
    localparam logic [ADDR_W-1:0] REG_DIVISOR = 12'h004;
    localparam logic [ADDR_W-1:0] REG_TXDATA  = 12'h008;
    localparam logic [ADDR_W-1:0] REG_RXDATA  = 12'h00C;
    localparam logic [ADDR_W-1:0] REG_CMD     = 12'h010;

    localparam int ST_CMD_READY        = 0;
    localparam int ST_BUS_IDLE         = 1;
    localparam int ST_DONE             = 2;
    localparam int ST_ACK_VALID        = 3;
    localparam int ST_ACK              = 4;
    localparam int ST_RD_DATA_VALID    = 5;
    localparam int ST_CMD_ILLEGAL      = 6;
    localparam int ST_MASTER_RECEIVING = 7;

    localparam logic [CMD_W-1:0] START_CMD   = 3'h0;
    localparam logic [CMD_W-1:0] WR_CMD      = 3'h1;
    localparam logic [CMD_W-1:0] RD_CMD      = 3'h2;
    localparam logic [CMD_W-1:0] STOP_CMD    = 3'h3;
    localparam logic [CMD_W-1:0] RESTART_CMD = 3'h4;

    logic clk;
    logic rst_n;

    // MMIO
    logic                    req_valid;
    logic                    req_ready;
    logic                    req_write;
    logic [ADDR_W-1:0]       req_addr;
    logic [DATA_W-1:0]       req_wdata;
    logic [(DATA_W/8)-1:0]   req_wstrb;

    logic                    rsp_valid;
    logic                    rsp_ready;
    logic [DATA_W-1:0]       rsp_rdata;
    logic                    rsp_err;

    // I2C top-level pins (held idle/high in this TB)
    logic sda_in;
    logic sda_out;
    logic scl_in;
    logic scl_out;
    logic master_receiving_o;

    // TB scratch
    logic [31:0] rd_data;
    logic        rd_err;
    logic        wr_err;
    integer      error_count;

    // ModelSim-safe helper values used by force statements
    logic        force_ack_value;
    logic [7:0]  force_rx_byte;

    //--------------------------------------------------------------------------
    // Clock
    //--------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;   // 50 MHz
    end

    //--------------------------------------------------------------------------
    // Keep external bus idle/high in this TB
    //--------------------------------------------------------------------------
    initial begin
        sda_in = 1'b1;
        scl_in = 1'b1;
    end

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    i2c_regs #(
        .ADDR_W      (ADDR_W),
        .DATA_W      (DATA_W),
        .BYTE_W      (BYTE_W),
        .CMD_W       (CMD_W),
        .DIVISOR_W   (DIVISOR_W),
        .MIN_DIVISOR (16'd4)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),

        .req_valid          (req_valid),
        .req_ready          (req_ready),
        .req_write          (req_write),
        .req_addr           (req_addr),
        .req_wdata          (req_wdata),
        .req_wstrb          (req_wstrb),

        .rsp_valid          (rsp_valid),
        .rsp_ready          (rsp_ready),
        .rsp_rdata          (rsp_rdata),
        .rsp_err            (rsp_err),

        .sda_in             (sda_in),
        .sda_out            (sda_out),
        .scl_in             (scl_in),
        .scl_out            (scl_out),
        .master_receiving_o (master_receiving_o)
    );

    //--------------------------------------------------------------------------
    // MMIO helpers
    //--------------------------------------------------------------------------
    task automatic mmio_write32(
        input  logic [ADDR_W-1:0] addr,
        input  logic [DATA_W-1:0] data,
        input  logic [(DATA_W/8)-1:0] strb,
        output logic err
    );
    begin
        @(posedge clk);
        req_valid <= 1'b1;
        req_write <= 1'b1;
        req_addr  <= addr;
        req_wdata <= data;
        req_wstrb <= strb;

        while (!req_ready) begin
            @(posedge clk);
        end

        @(posedge clk);
        req_valid <= 1'b0;
        req_write <= 1'b0;
        req_addr  <= '0;
        req_wdata <= '0;
        req_wstrb <= '0;

        while (!rsp_valid) begin
            @(posedge clk);
        end

        err = rsp_err;
        @(posedge clk);
    end
    endtask

    task automatic mmio_read32(
        input  logic [ADDR_W-1:0] addr,
        output logic [DATA_W-1:0] data,
        output logic err
    );
    begin
        @(posedge clk);
        req_valid <= 1'b1;
        req_write <= 1'b0;
        req_addr  <= addr;
        req_wdata <= '0;
        req_wstrb <= '0;

        while (!req_ready) begin
            @(posedge clk);
        end

        @(posedge clk);
        req_valid <= 1'b0;
        req_addr  <= '0;

        while (!rsp_valid) begin
            @(posedge clk);
        end

        data = rsp_rdata;
        err  = rsp_err;
        @(posedge clk);
    end
    endtask

    task automatic status_read(output logic [31:0] st);
    begin
        mmio_read32(REG_STATUS, st, rd_err);
        if (rd_err) begin
            $display("[%0t] ERROR: status read returned rsp_err", $time);
            error_count = error_count + 1;
        end
    end
    endtask

    task automatic clear_status_bits(input logic [31:0] mask);
    begin
        mmio_write32(REG_STATUS, mask, 4'hF, wr_err);
        if (wr_err) begin
            $display("[%0t] ERROR: REG_STATUS W1C write returned rsp_err", $time);
            error_count = error_count + 1;
        end
    end
    endtask

    task automatic issue_cmd(
        input logic [CMD_W-1:0] cmd,
        input logic             rd_last
    );
        logic [31:0] cmd_word;
    begin
        cmd_word = '0;
        cmd_word[CMD_W-1:0] = cmd;
        cmd_word[8]         = rd_last;

        mmio_write32(REG_CMD, cmd_word, 4'h1, wr_err);
        if (wr_err) begin
            $display("[%0t] ERROR: REG_CMD write returned rsp_err (cmd=0x%0x)", $time, cmd);
            error_count = error_count + 1;
        end
    end
    endtask

    //--------------------------------------------------------------------------
    // Force-based event helpers
    //
    // These are register-block tests. The core is not being functionally
    // validated here. We directly drive the internal core-to-regs status/event
    // signals to verify sticky bits, W1C, and auto-clear behavior.
    //--------------------------------------------------------------------------
    task automatic pulse_done;
    begin
        @(negedge clk);
        force dut.i2c_done_tick = 1'b1;
        @(posedge clk);
        @(negedge clk);
        force dut.i2c_done_tick = 1'b0;
    end
    endtask

    task automatic pulse_ack_result(input logic ack_value);
    begin
        force_ack_value = ack_value;

        @(negedge clk);
        force dut.i2c_ack       = force_ack_value;
        force dut.i2c_ack_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        force dut.i2c_ack_valid = 1'b0;
        force dut.i2c_ack       = 1'b0;
    end
    endtask

    task automatic pulse_rd_byte(input logic [7:0] byte_value);
    begin
        force_rx_byte = byte_value;

        @(negedge clk);
        force dut.i2c_rx_data       = force_rx_byte;
        force dut.i2c_rd_data_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        force dut.i2c_rd_data_valid = 1'b0;
        force dut.i2c_rx_data       = 8'h00;
    end
    endtask

    task automatic pulse_illegal;
    begin
        @(negedge clk);
        force dut.i2c_cmd_illegal = 1'b1;
        @(posedge clk);
        @(negedge clk);
        force dut.i2c_cmd_illegal = 1'b0;
    end
    endtask

    //--------------------------------------------------------------------------
    // Checks
    //--------------------------------------------------------------------------
    task automatic expect_bit_set(
        input logic [31:0] value,
        input int          bit_idx,
        input string       name
    );
    begin
        if (!value[bit_idx]) begin
            $display("[%0t] ERROR: expected %s to be 1", $time, name);
            error_count = error_count + 1;
        end
    end
    endtask

    task automatic expect_bit_clear(
        input logic [31:0] value,
        input int          bit_idx,
        input string       name
    );
    begin
        if (value[bit_idx]) begin
            $display("[%0t] ERROR: expected %s to be 0", $time, name);
            error_count = error_count + 1;
        end
    end
    endtask

    task automatic expect_eq8(
        input logic [7:0] got,
        input logic [7:0] exp,
        input string      name
    );
    begin
        if (got !== exp) begin
            $display("[%0t] ERROR: %s mismatch. got=0x%02x exp=0x%02x", $time, name, got, exp);
            error_count = error_count + 1;
        end
    end
    endtask

    //--------------------------------------------------------------------------
    // Test sequence
    //--------------------------------------------------------------------------
    initial begin
        error_count      = 0;
        req_valid        = 1'b0;
        req_write        = 1'b0;
        req_addr         = '0;
        req_wdata        = '0;
        req_wstrb        = '0;
        rsp_ready        = 1'b1;
        rst_n            = 1'b0;
        rd_data          = '0;
        rd_err           = 1'b0;
        wr_err           = 1'b0;
        force_ack_value  = 1'b0;
        force_rx_byte    = 8'h00;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Force stable internal "core output" view for register testing
        force dut.i2c_cmd_ready        = 1'b1;
        force dut.i2c_bus_idle         = 1'b1;
        force dut.i2c_master_receiving = 1'b0;
        force dut.i2c_done_tick        = 1'b0;
        force dut.i2c_ack_valid        = 1'b0;
        force dut.i2c_ack              = 1'b0;
        force dut.i2c_rd_data_valid    = 1'b0;
        force dut.i2c_cmd_illegal      = 1'b0;
        force dut.i2c_rx_data          = 8'h00;

        //----------------------------------------------------------------------
        // Initial live status
        //----------------------------------------------------------------------
        $display("[%0t] INFO: read initial status", $time);
        status_read(rd_data);
        expect_bit_set  (rd_data, ST_CMD_READY,        "cmd_ready");
        expect_bit_set  (rd_data, ST_BUS_IDLE,         "bus_idle");
        expect_bit_clear(rd_data, ST_DONE,             "done");
        expect_bit_clear(rd_data, ST_ACK_VALID,        "ack_valid");
        expect_bit_clear(rd_data, ST_RD_DATA_VALID,    "rd_data_valid");
        expect_bit_clear(rd_data, ST_CMD_ILLEGAL,      "cmd_illegal");
        expect_bit_clear(rd_data, ST_MASTER_RECEIVING, "master_receiving");

        //----------------------------------------------------------------------
        // Basic register writes
        //----------------------------------------------------------------------
        $display("[%0t] INFO: program divisor and TXDATA", $time);
        mmio_write32(REG_DIVISOR, 32'd8, 4'hF, wr_err);
        if (wr_err) begin
            $display("[%0t] ERROR: divisor write returned rsp_err", $time);
            error_count = error_count + 1;
        end

        mmio_write32(REG_TXDATA, 32'h000000A5, 4'h1, wr_err);
        if (wr_err) begin
            $display("[%0t] ERROR: txdata write returned rsp_err", $time);
            error_count = error_count + 1;
        end

        //----------------------------------------------------------------------
        // Sticky DONE
        //----------------------------------------------------------------------
        $display("[%0t] INFO: pulse done event", $time);
        pulse_done();

        status_read(rd_data);
        expect_bit_set(rd_data, ST_DONE, "done sticky set");

        status_read(rd_data);
        expect_bit_set(rd_data, ST_DONE, "done sticky persists");

        clear_status_bits(32'(1 << ST_DONE));
        status_read(rd_data);
        expect_bit_clear(rd_data, ST_DONE, "done cleared by W1C");

        //----------------------------------------------------------------------
        // Sticky ACK_VALID + ACK
        //----------------------------------------------------------------------
        $display("[%0t] INFO: pulse ACK result", $time);
        pulse_ack_result(1'b0);   // 0 = ACK

        status_read(rd_data);
        expect_bit_set  (rd_data, ST_ACK_VALID, "ack_valid sticky set");
        expect_bit_clear(rd_data, ST_ACK,       "ack latched low for ACK");

        clear_status_bits((32'(1 << ST_ACK_VALID)) | (32'(1 << ST_ACK)));
        status_read(rd_data);
        expect_bit_clear(rd_data, ST_ACK_VALID, "ack_valid cleared by W1C");
        expect_bit_clear(rd_data, ST_ACK,       "ack cleared by W1C");

        //----------------------------------------------------------------------
        // Sticky READ-DATA + RXDATA capture
        //----------------------------------------------------------------------
        $display("[%0t] INFO: pulse read-data event", $time);
        pulse_rd_byte(8'h3C);

        status_read(rd_data);
        expect_bit_set(rd_data, ST_RD_DATA_VALID, "rd_data_valid sticky set");

        mmio_read32(REG_RXDATA, rd_data, rd_err);
        if (rd_err) begin
            $display("[%0t] ERROR: rxdata read returned rsp_err", $time);
            error_count = error_count + 1;
        end
        expect_eq8(rd_data[7:0], 8'h3C, "rxdata_reg");

        clear_status_bits(32'(1 << ST_RD_DATA_VALID));
        status_read(rd_data);
        expect_bit_clear(rd_data, ST_RD_DATA_VALID, "rd_data_valid cleared by W1C");

        //----------------------------------------------------------------------
        // Sticky ILLEGAL
        //----------------------------------------------------------------------
        $display("[%0t] INFO: pulse illegal-command event", $time);
        pulse_illegal();

        status_read(rd_data);
        expect_bit_set(rd_data, ST_CMD_ILLEGAL, "cmd_illegal sticky set");

        clear_status_bits(32'(1 << ST_CMD_ILLEGAL));
        status_read(rd_data);
        expect_bit_clear(rd_data, ST_CMD_ILLEGAL, "cmd_illegal cleared by W1C");

        //----------------------------------------------------------------------
        // Auto-clear on new command launch
        //----------------------------------------------------------------------
        $display("[%0t] INFO: verify auto-clear on command launch", $time);

        pulse_done();
        pulse_ack_result(1'b1);   // 1 = NACK
        pulse_rd_byte(8'h55);
        pulse_illegal();

        status_read(rd_data);
        expect_bit_set(rd_data, ST_DONE,          "done before auto-clear");
        expect_bit_set(rd_data, ST_ACK_VALID,     "ack_valid before auto-clear");
        expect_bit_set(rd_data, ST_ACK,           "ack before auto-clear");
        expect_bit_set(rd_data, ST_RD_DATA_VALID, "rd_data_valid before auto-clear");
        expect_bit_set(rd_data, ST_CMD_ILLEGAL,   "cmd_illegal before auto-clear");

        issue_cmd(START_CMD, 1'b0);

        status_read(rd_data);
        expect_bit_clear(rd_data, ST_DONE,          "done auto-cleared on command launch");
        expect_bit_clear(rd_data, ST_ACK_VALID,     "ack_valid auto-cleared on command launch");
        expect_bit_clear(rd_data, ST_ACK,           "ack auto-cleared on command launch");
        expect_bit_clear(rd_data, ST_RD_DATA_VALID, "rd_data_valid auto-cleared on command launch");
        expect_bit_clear(rd_data, ST_CMD_ILLEGAL,   "cmd_illegal auto-cleared on command launch");

        //----------------------------------------------------------------------
        // Additional command encodings should also be accepted when cmd_ready=1
        //----------------------------------------------------------------------
        $display("[%0t] INFO: sanity-check a few command writes", $time);
        issue_cmd(WR_CMD,      1'b0);
        issue_cmd(RD_CMD,      1'b1);
        issue_cmd(RESTART_CMD, 1'b0);
        issue_cmd(STOP_CMD,    1'b0);

        //----------------------------------------------------------------------
        // REG_STATUS write should now be legal
        //----------------------------------------------------------------------
        $display("[%0t] INFO: verify REG_STATUS write is accepted", $time);
        mmio_write32(REG_STATUS, 32'h00000000, 4'hF, wr_err);
        if (wr_err) begin
            $display("[%0t] ERROR: REG_STATUS write should not return rsp_err", $time);
            error_count = error_count + 1;
        end

        repeat (10) @(posedge clk);

        if (error_count == 0) begin
            $display("[%0t] PASS: tb_i2c_regs completed with no errors", $time);
        end else begin
            $display("[%0t] FAIL: tb_i2c_regs completed with %0d error(s)", $time, error_count);
        end

        $finish;
    end

endmodule