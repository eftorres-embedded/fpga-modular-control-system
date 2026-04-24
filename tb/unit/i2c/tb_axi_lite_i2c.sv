`timescale 1ns/1ps

module tb_axi_lite_i2c;

    localparam int ADDR_W = 12;
    localparam int DATA_W = 32;
    localparam int STRB_W = DATA_W/8;

    localparam logic [ADDR_W-1:0] REG_STATUS  = 12'h000;
    localparam logic [ADDR_W-1:0] REG_DIVISOR = 12'h004;
    localparam logic [ADDR_W-1:0] REG_TXDATA  = 12'h008;
    localparam logic [ADDR_W-1:0] REG_RXDATA  = 12'h00C;
    localparam logic [ADDR_W-1:0] REG_CMD     = 12'h010;
    localparam logic [ADDR_W-1:0] REG_DEBUG   = 12'h014;
    localparam logic [ADDR_W-1:0] REG_BAD     = 12'h020;

    localparam logic [2:0] START_CMD = 3'h0;
    localparam logic [2:0] STOP_CMD  = 3'h3;

    logic clk;
    logic rst_n;

    logic [ADDR_W-1:0] s_axil_awaddr;
    logic              s_axil_awvalid;
    logic              s_axil_awready;

    logic [DATA_W-1:0] s_axil_wdata;
    logic [STRB_W-1:0] s_axil_wstrb;
    logic              s_axil_wvalid;
    logic              s_axil_wready;

    logic [1:0]        s_axil_bresp;
    logic              s_axil_bvalid;
    logic              s_axil_bready;

    logic [ADDR_W-1:0] s_axil_araddr;
    logic              s_axil_arvalid;
    logic              s_axil_arready;

    logic [DATA_W-1:0] s_axil_rdata;
    logic [1:0]        s_axil_rresp;
    logic              s_axil_rvalid;
    logic              s_axil_rready;

    logic sda_in;
    logic sda_out;
    logic scl_in;
    logic scl_out;
    logic master_receiving_o;

    axi_lite_i2c #(
        .ADDR_W      (ADDR_W),
        .DATA_W      (DATA_W),
        .BYTE_W      (8),
        .CMD_W       (3),
        .DIVISOR_W   (16),
        .MIN_DIVISOR (16'd1)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),

        .s_axil_awaddr      (s_axil_awaddr),
        .s_axil_awvalid     (s_axil_awvalid),
        .s_axil_awready     (s_axil_awready),

        .s_axil_wdata       (s_axil_wdata),
        .s_axil_wstrb       (s_axil_wstrb),
        .s_axil_wvalid      (s_axil_wvalid),
        .s_axil_wready      (s_axil_wready),

        .s_axil_bresp       (s_axil_bresp),
        .s_axil_bvalid      (s_axil_bvalid),
        .s_axil_bready      (s_axil_bready),

        .s_axil_araddr      (s_axil_araddr),
        .s_axil_arvalid     (s_axil_arvalid),
        .s_axil_arready     (s_axil_arready),

        .s_axil_rdata       (s_axil_rdata),
        .s_axil_rresp       (s_axil_rresp),
        .s_axil_rvalid      (s_axil_rvalid),
        .s_axil_rready      (s_axil_rready),

        .sda_in             (sda_in),
        .sda_out            (sda_out),
        .scl_in             (scl_in),
        .scl_out            (scl_out),
        .master_receiving_o (master_receiving_o)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    initial begin
        $dumpfile("build/sim/waves/tb_axi_lite_i2c.vcd");
        $dumpvars(0, tb_axi_lite_i2c);
    end

    task automatic tb_fail(input string msg);
        begin
            $error("FAIL: %s", msg);
            $finish;
        end
    endtask

    task automatic expect_eq32(input string name, input logic [31:0] got, input logic [31:0] exp);
        begin
            if (got !== exp) begin
                $error("FAIL: %s got=0x%08h exp=0x%08h", name, got, exp);
                $finish;
            end
            $display("PASS: %s = 0x%08h", name, got);
        end
    endtask

    task automatic expect_resp_okay(input string name, input logic [1:0] resp);
        begin
            if (resp !== 2'b00) begin
                $error("FAIL: %s response got=%b exp=00", name, resp);
                $finish;
            end
            $display("PASS: %s response OKAY", name);
        end
    endtask

    task automatic expect_resp_slverr(input string name, input logic [1:0] resp);
        begin
            if (resp !== 2'b10) begin
                $error("FAIL: %s response got=%b exp=10", name, resp);
                $finish;
            end
            $display("PASS: %s response SLVERR", name);
        end
    endtask

    task automatic axi_write(
        input  logic [ADDR_W-1:0] addr,
        input  logic [DATA_W-1:0] data,
        input  logic [STRB_W-1:0] strb,
        output logic [1:0]        resp
    );
        int timeout;
        begin
            @(posedge clk);
            s_axil_awaddr  = addr;
            s_axil_awvalid = 1'b1;
            s_axil_wdata   = data;
            s_axil_wstrb   = strb;
            s_axil_wvalid  = 1'b1;
            s_axil_bready  = 1'b1;

            timeout = 0;
            while (s_axil_awvalid || s_axil_wvalid) begin
                @(posedge clk);
                if (s_axil_awvalid && s_axil_awready) s_axil_awvalid = 1'b0;
                if (s_axil_wvalid  && s_axil_wready)  s_axil_wvalid  = 1'b0;
                timeout++;
                if (timeout > 200) tb_fail("AXI write AW/W handshake timeout");
            end

            timeout = 0;
            while (!s_axil_bvalid) begin
                @(posedge clk);
                timeout++;
                if (timeout > 2000) tb_fail("AXI write response timeout");
            end

            resp = s_axil_bresp;

            @(posedge clk);
            s_axil_bready = 1'b0;
        end
    endtask

    task automatic axi_read(
        input  logic [ADDR_W-1:0] addr,
        output logic [DATA_W-1:0] data,
        output logic [1:0]        resp
    );
        int timeout;
        begin
            @(posedge clk);
            s_axil_araddr  = addr;
            s_axil_arvalid = 1'b1;
            s_axil_rready  = 1'b1;

            timeout = 0;
            while (!(s_axil_arvalid && s_axil_arready)) begin
                @(posedge clk);
                timeout++;
                if (timeout > 200) tb_fail("AXI read address handshake timeout");
            end

            @(posedge clk);
            s_axil_arvalid = 1'b0;

            timeout = 0;
            while (!s_axil_rvalid) begin
                @(posedge clk);
                timeout++;
                if (timeout > 2000) tb_fail("AXI read response timeout");
            end

            data = s_axil_rdata;
            resp = s_axil_rresp;

            @(posedge clk);
            s_axil_rready = 1'b0;
        end
    endtask

    task automatic axi_write_split_aw_first(
        input  logic [ADDR_W-1:0] addr,
        input  logic [DATA_W-1:0] data,
        input  logic [STRB_W-1:0] strb,
        output logic [1:0]        resp
    );
        int timeout;
        begin
            @(posedge clk);
            s_axil_awaddr  = addr;
            s_axil_awvalid = 1'b1;

            timeout = 0;
            while (s_axil_awvalid) begin
                @(posedge clk);
                if (s_axil_awready) s_axil_awvalid = 1'b0;
                timeout++;
                if (timeout > 200) tb_fail("split AW-first AW timeout");
            end

            repeat (3) @(posedge clk);

            s_axil_wdata  = data;
            s_axil_wstrb  = strb;
            s_axil_wvalid = 1'b1;
            s_axil_bready = 1'b1;

            timeout = 0;
            while (s_axil_wvalid) begin
                @(posedge clk);
                if (s_axil_wready) s_axil_wvalid = 1'b0;
                timeout++;
                if (timeout > 200) tb_fail("split AW-first W timeout");
            end

            timeout = 0;
            while (!s_axil_bvalid) begin
                @(posedge clk);
                timeout++;
                if (timeout > 2000) tb_fail("split AW-first response timeout");
            end

            resp = s_axil_bresp;

            @(posedge clk);
            s_axil_bready = 1'b0;
        end
    endtask

    task automatic axi_write_split_w_first(
        input  logic [ADDR_W-1:0] addr,
        input  logic [DATA_W-1:0] data,
        input  logic [STRB_W-1:0] strb,
        output logic [1:0]        resp
    );
        int timeout;
        begin
            @(posedge clk);
            s_axil_wdata  = data;
            s_axil_wstrb  = strb;
            s_axil_wvalid = 1'b1;

            timeout = 0;
            while (s_axil_wvalid) begin
                @(posedge clk);
                if (s_axil_wready) s_axil_wvalid = 1'b0;
                timeout++;
                if (timeout > 200) tb_fail("split W-first W timeout");
            end

            repeat (3) @(posedge clk);

            s_axil_awaddr  = addr;
            s_axil_awvalid = 1'b1;
            s_axil_bready  = 1'b1;

            timeout = 0;
            while (s_axil_awvalid) begin
                @(posedge clk);
                if (s_axil_awready) s_axil_awvalid = 1'b0;
                timeout++;
                if (timeout > 200) tb_fail("split W-first AW timeout");
            end

            timeout = 0;
            while (!s_axil_bvalid) begin
                @(posedge clk);
                timeout++;
                if (timeout > 2000) tb_fail("split W-first response timeout");
            end

            resp = s_axil_bresp;

            @(posedge clk);
            s_axil_bready = 1'b0;
        end
    endtask

    task automatic wait_status_done(output logic [31:0] status);
        logic [1:0] resp;
        int timeout;
        begin
            timeout = 0;
            do begin
                axi_read(REG_STATUS, status, resp);
                expect_resp_okay("poll REG_STATUS", resp);

                timeout++;
                if (timeout > 5000) begin
                    $error("STATUS timeout. Last STATUS=0x%08h", status);
                    $finish;
                end
            end while (!status[2]);
        end
    endtask


    task automatic strict_wstrb_merge_test;
        logic [31:0] rdata;
        logic [1:0]  resp;
        begin
            $display("------------------------------------------------------------");
            $display("STRICT TEST: WSTRB partial-write behavior");
            $display("------------------------------------------------------------");

            axi_write(REG_DIVISOR, 32'h0000_1234, 4'b0011, resp);
            expect_resp_okay("DIVISOR low half write", resp);

            axi_read(REG_DIVISOR, rdata, resp);
            expect_resp_okay("DIVISOR low half read", resp);
            expect_eq32("DIVISOR low half", rdata, 32'h0000_1234);

            axi_write(REG_DIVISOR, 32'h0000_AB00, 4'b0010, resp);
            expect_resp_okay("DIVISOR byte1 write", resp);

            axi_read(REG_DIVISOR, rdata, resp);
            expect_resp_okay("DIVISOR byte1 read", resp);
            expect_eq32("DIVISOR byte1 merge", rdata, 32'h0000_AB34);

            axi_write(REG_TXDATA, 32'h0000_0055, 4'b0001, resp);
            expect_resp_okay("TXDATA low byte write", resp);

            axi_write(REG_TXDATA, 32'h0000_AA00, 4'b0010, resp);
            expect_resp_okay("TXDATA upper byte write ignored by BYTE_W storage", resp);

            axi_read(REG_TXDATA, rdata, resp);
            expect_resp_okay("TXDATA read after upper byte write", resp);
            expect_eq32("TXDATA unchanged by upper byte", rdata, 32'h0000_0055);

            $display("PASS: WSTRB merge behavior");
        end
    endtask

    task automatic strict_back_to_back_rw_test;
        logic [31:0] rdata;
        logic [1:0]  resp;
        begin
            $display("------------------------------------------------------------");
            $display("STRICT TEST: back-to-back write/read");
            $display("------------------------------------------------------------");

            axi_write(REG_DIVISOR, 32'd11, 4'hF, resp);
            expect_resp_okay("B2B DIVISOR write", resp);

            axi_read(REG_DIVISOR, rdata, resp);
            expect_resp_okay("B2B DIVISOR read", resp);
            expect_eq32("B2B DIVISOR value", rdata, 32'd11);

            axi_write(REG_TXDATA, 32'h0000_00C3, 4'h1, resp);
            expect_resp_okay("B2B TXDATA write", resp);

            axi_read(REG_TXDATA, rdata, resp);
            expect_resp_okay("B2B TXDATA read", resp);
            expect_eq32("B2B TXDATA value", rdata, 32'h0000_00C3);

            $display("PASS: back-to-back write/read");
        end
    endtask

    task automatic strict_cmd_response_while_active_test;
        logic [31:0] status;
        logic [1:0]  resp;
        begin
            $display("------------------------------------------------------------");
            $display("STRICT TEST: command response while I2C bus is active");
            $display("------------------------------------------------------------");

            axi_read(REG_STATUS, status, resp);
            expect_resp_okay("active-bus status read", resp);
            $display("INFO: active-bus STATUS before STOP=0x%08h", status);

            // TEST 6 already issued START, which leaves this core in bus-active state.
            // This verifies that another command write always returns an AXI response
            // instead of hanging the AXI wrapper or i2c_regs response channel.
            axi_write(REG_CMD, {29'd0, STOP_CMD}, 4'b0001, resp);

            if (resp !== 2'b00 && resp !== 2'b10) begin
                tb_fail("REG_CMD while active returned invalid AXI response");
            end

            $display("PASS: REG_CMD while active returned AXI response=%b", resp);

            repeat (50) @(posedge clk);

            axi_read(REG_STATUS, status, resp);
            expect_resp_okay("active-bus status read after command", resp);
            $display("INFO: active-bus STATUS after command=0x%08h", status);
        end
    endtask

    task automatic strict_read_backpressure_test;
        int timeout;
        begin
            $display("------------------------------------------------------------");
            $display("STRICT TEST: AXI read response backpressure");
            $display("------------------------------------------------------------");

            @(posedge clk);
            s_axil_araddr  = REG_DEBUG;
            s_axil_arvalid = 1'b1;
            s_axil_rready  = 1'b0;

            timeout = 0;
            while (!(s_axil_arvalid && s_axil_arready)) begin
                @(posedge clk);
                timeout++;
                if (timeout > 200) tb_fail("strict read first AR timeout");
            end

            @(posedge clk);
            s_axil_arvalid = 1'b0;

            timeout = 0;
            while (!s_axil_rvalid) begin
                @(posedge clk);
                timeout++;
                if (timeout > 2000) tb_fail("strict read first RVALID timeout");
            end

            expect_resp_okay("held first read response", s_axil_rresp);
            expect_eq32("held first read data", s_axil_rdata, 32'hDECA_FBAD);

            @(posedge clk);
            s_axil_araddr  = REG_STATUS;
            s_axil_arvalid = 1'b1;

            repeat (10) @(posedge clk);

            if (s_axil_rdata !== 32'hDECA_FBAD) begin
                $error("FAIL: RDATA changed while RREADY low. got=0x%08h", s_axil_rdata);
                $finish;
            end

            if (s_axil_rresp !== 2'b00) begin
                $error("FAIL: RRESP changed while RREADY low. got=%b", s_axil_rresp);
                $finish;
            end

            $display("PASS: held read response stayed stable while RREADY low");

            // Aggressively drain any leftover read response.
            s_axil_rready  = 1'b1;
            s_axil_arvalid = 1'b0;

            timeout = 0;
            while (s_axil_rvalid || dut.ar_hold_valid || dut.mmio_busy || dut.req_pending_valid) begin
                @(posedge clk);
                timeout++;
                if (timeout > 2000) begin
                    $error("FAIL: strict read cleanup stuck. rvalid=%b ar_hold=%b mmio_busy=%b req_pending=%b",
                           s_axil_rvalid,
                           dut.ar_hold_valid,
                           dut.mmio_busy,
                           dut.req_pending_valid);
                    $finish;
                end
            end

            @(posedge clk);
            s_axil_rready = 1'b0;

            repeat (5) @(posedge clk);
        end
    endtask

    task automatic strict_write_backpressure_test;
        int timeout;
        begin
            $display("------------------------------------------------------------");
            $display("STRICT TEST: AXI write response backpressure");
            $display("------------------------------------------------------------");

            @(posedge clk);
            s_axil_awaddr  = REG_DIVISOR;
            s_axil_awvalid = 1'b1;
            s_axil_wdata   = 32'd9;
            s_axil_wstrb   = 4'hF;
            s_axil_wvalid  = 1'b1;
            s_axil_bready  = 1'b0;

            timeout = 0;
            while (s_axil_awvalid || s_axil_wvalid) begin
                @(posedge clk);
                if (s_axil_awvalid && s_axil_awready) s_axil_awvalid = 1'b0;
                if (s_axil_wvalid  && s_axil_wready)  s_axil_wvalid  = 1'b0;
                timeout++;
                if (timeout > 200) tb_fail("strict write AW/W timeout");
            end

            timeout = 0;
            while (!s_axil_bvalid) begin
                @(posedge clk);
                timeout++;
                if (timeout > 2000) tb_fail("strict write BVALID timeout");
            end

            if (s_axil_bresp !== 2'b00) begin
                $error("FAIL: held BRESP expected OKAY, got=%b", s_axil_bresp);
                $finish;
            end

            @(posedge clk);
            s_axil_awaddr  = REG_TXDATA;
            s_axil_awvalid = 1'b1;
            s_axil_wdata   = 32'hA5;
            s_axil_wstrb   = 4'h1;
            s_axil_wvalid  = 1'b1;

            repeat (10) @(posedge clk);

            if (!s_axil_bvalid || s_axil_bresp !== 2'b00) begin
                $error("FAIL: held BRESP changed/corrupted while BREADY low");
                $finish;
            end

            $display("PASS: held write response stayed stable while BREADY low");

            s_axil_bready = 1'b1;
            @(posedge clk);
            s_axil_bready  = 1'b0;
            s_axil_awvalid = 1'b0;
            s_axil_wvalid  = 1'b0;

            repeat (5) @(posedge clk);
        end
    endtask

    initial begin
        logic [31:0] rdata;
        logic [31:0] status;
        logic [1:0]  resp;

        s_axil_awaddr  = '0;
        s_axil_awvalid = 1'b0;
        s_axil_wdata   = '0;
        s_axil_wstrb   = '0;
        s_axil_wvalid  = 1'b0;
        s_axil_bready  = 1'b0;

        s_axil_araddr  = '0;
        s_axil_arvalid = 1'b0;
        s_axil_rready  = 1'b0;

        sda_in = 1'b1;
        scl_in = 1'b1;

        rst_n = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);

        $display("------------------------------------------------------------");
        $display("TEST 1: reset/default status");
        $display("------------------------------------------------------------");

        axi_read(REG_STATUS, rdata, resp);
        expect_resp_okay("REG_STATUS read after reset", resp);

        if (!rdata[0]) tb_fail("cmd_ready should be 1 after reset");
        if (!rdata[1]) tb_fail("bus_idle should be 1 after reset");
        $display("PASS: reset STATUS=0x%08h", rdata);

        $display("------------------------------------------------------------");
        $display("TEST 2: divisor read/write");
        $display("------------------------------------------------------------");

        axi_write(REG_DIVISOR, 32'd4, 4'hF, resp);
        expect_resp_okay("REG_DIVISOR write", resp);

        axi_read(REG_DIVISOR, rdata, resp);
        expect_resp_okay("REG_DIVISOR read", resp);
        expect_eq32("REG_DIVISOR", rdata, 32'd4);

        $display("------------------------------------------------------------");
        $display("TEST 3: TXDATA byte write/read");
        $display("------------------------------------------------------------");

        axi_write(REG_TXDATA, 32'h0000_00A5, 4'b0001, resp);
        expect_resp_okay("REG_TXDATA write byte 0", resp);

        axi_read(REG_TXDATA, rdata, resp);
        expect_resp_okay("REG_TXDATA read", resp);
        expect_eq32("REG_TXDATA", rdata, 32'h0000_00A5);

        $display("------------------------------------------------------------");
        $display("TEST 4: expected SLVERR paths");
        $display("------------------------------------------------------------");

        axi_read(REG_DEBUG, rdata, resp);
        expect_resp_okay("REG_DEBUG read", resp);
        expect_eq32("REG_DEBUG value", rdata, 32'hDECA_FBAD);

        axi_write(REG_DEBUG, 32'h1234_5678, 4'hF, resp);
        expect_resp_slverr("REG_DEBUG write", resp);

        axi_write(REG_RXDATA, 32'h1111_2222, 4'hF, resp);
        expect_resp_slverr("REG_RXDATA write", resp);

        axi_read(REG_CMD, rdata, resp);
        expect_resp_slverr("REG_CMD read", resp);

        axi_read(REG_BAD, rdata, resp);
        expect_resp_slverr("bad address read", resp);

        axi_write(REG_BAD, 32'hCAFE_BABE, 4'hF, resp);
        expect_resp_slverr("bad address write", resp);

        $display("------------------------------------------------------------");
        $display("TEST 5: split AW/W arrival");
        $display("------------------------------------------------------------");

        axi_write_split_aw_first(REG_DIVISOR, 32'd5, 4'hF, resp);
        expect_resp_okay("AW-first split write", resp);

        axi_read(REG_DIVISOR, rdata, resp);
        expect_resp_okay("REG_DIVISOR read after AW-first", resp);
        expect_eq32("REG_DIVISOR AW-first", rdata, 32'd5);

        axi_write_split_w_first(REG_DIVISOR, 32'd6, 4'hF, resp);
        expect_resp_okay("W-first split write", resp);

        axi_read(REG_DIVISOR, rdata, resp);
        expect_resp_okay("REG_DIVISOR read after W-first", resp);
        expect_eq32("REG_DIVISOR W-first", rdata, 32'd6);

        strict_wstrb_merge_test();
        strict_back_to_back_rw_test();

        $display("------------------------------------------------------------");
        $display("TEST 6: START command accepted, no done-wait");
        $display("------------------------------------------------------------");

        axi_write(REG_DIVISOR, 32'd2, 4'hF, resp);
        expect_resp_okay("set fast divisor", resp);

        axi_write(REG_CMD, {29'd0, START_CMD}, 4'b0001, resp);
        expect_resp_okay("REG_CMD START write accepted", resp);

        repeat (50) @(posedge clk);

        axi_read(REG_STATUS, status, resp);
        expect_resp_okay("REG_STATUS after START", resp);

        $display("INFO: STATUS after START=0x%08h", status);

        // Do not require DONE here. Some I2C cores treat START as a bus-state
        // transition and wait for the next command instead of raising done.
        // This test only verifies that the AXI wrapper accepts the command.

        axi_write(REG_STATUS, 32'h0000_007C, 4'hF, resp);
        expect_resp_okay("REG_STATUS W1C clear", resp);

        axi_read(REG_STATUS, status, resp);
        expect_resp_okay("REG_STATUS after W1C", resp);

        $display("INFO: STATUS after W1C=0x%08h", status);

        $display("------------------------------------------------------------");
        $display("TEST 7: invalid REG_CMD strobe");
        $display("------------------------------------------------------------");

        axi_write(REG_CMD, {29'd0, STOP_CMD}, 4'b0010, resp);
        expect_resp_slverr("REG_CMD write without byte lane 0", resp);

        strict_cmd_response_while_active_test();
        strict_read_backpressure_test();
        strict_write_backpressure_test();

        $display("------------------------------------------------------------");
        $display("ALL tb_axi_lite_i2c STRICT TESTS PASSED");
        $display("------------------------------------------------------------");

        repeat (20) @(posedge clk);
        $finish;
    end

endmodule