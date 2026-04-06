// tb_spi_regs.sv
// Testbench scaffold generated with assistance from ChatGPT (OpenAI)
// Modified and validated by Eder Torres

`timescale 1ns/1ps

module tb_axi_lite_spi;

    localparam int unsigned ADDR_W   = 12;
    localparam int unsigned DATA_W   = 32;

    localparam bit          CPOL     = 1'b0;
    localparam bit          CPHA     = 1'b1;
    localparam string       BITORDER = "MSB_FIRST";
    localparam int unsigned SPI_DW   = 8;
    localparam int unsigned CLKDIV   = 8;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    //--------------------------------------------------------------------------
    // DUT I/O
    //--------------------------------------------------------------------------
    logic                         clk;
    logic                         rst_n;

    logic [ADDR_W-1:0]            s_axil_awaddr;
    logic                         s_axil_awvalid;
    logic                         s_axil_awready;

    logic [DATA_W-1:0]            s_axil_wdata;
    logic [(DATA_W/8)-1:0]        s_axil_wstrb;
    logic                         s_axil_wvalid;
    logic                         s_axil_wready;

    logic [1:0]                   s_axil_bresp;
    logic                         s_axil_bvalid;
    logic                         s_axil_bready;

    logic [ADDR_W-1:0]            s_axil_araddr;
    logic                         s_axil_arvalid;
    logic                         s_axil_arready;

    logic [DATA_W-1:0]            s_axil_rdata;
    logic [1:0]                   s_axil_rresp;
    logic                         s_axil_rvalid;
    logic                         s_axil_rready;

    logic                         irq;
    logic                         spi_sclk;
    logic                         spi_mosi;
    logic                         spi_miso;
    logic                         spi_cs_n;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    axi_lite_spi #(
        .ADDR_W   (ADDR_W),
        .DATA_W   (DATA_W),
        .CPOL     (CPOL),
        .CPHA     (CPHA),
        .BITORDER (BITORDER),
        .SPI_DW   (SPI_DW),
        .CLKDIV   (CLKDIV)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),

        .s_axil_awaddr  (s_axil_awaddr),
        .s_axil_awvalid (s_axil_awvalid),
        .s_axil_awready (s_axil_awready),

        .s_axil_wdata   (s_axil_wdata),
        .s_axil_wstrb   (s_axil_wstrb),
        .s_axil_wvalid  (s_axil_wvalid),
        .s_axil_wready  (s_axil_wready),

        .s_axil_bresp   (s_axil_bresp),
        .s_axil_bvalid  (s_axil_bvalid),
        .s_axil_bready  (s_axil_bready),

        .s_axil_araddr  (s_axil_araddr),
        .s_axil_arvalid (s_axil_arvalid),
        .s_axil_arready (s_axil_arready),

        .s_axil_rdata   (s_axil_rdata),
        .s_axil_rresp   (s_axil_rresp),
        .s_axil_rvalid  (s_axil_rvalid),
        .s_axil_rready  (s_axil_rready),

        .irq            (irq),
        .spi_sclk       (spi_sclk),
        .spi_mosi       (spi_mosi),
        .spi_miso       (spi_miso),
        .spi_cs_n       (spi_cs_n)
    );

    //--------------------------------------------------------------------------
    // Clock
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    //--------------------------------------------------------------------------
    // Helpers
    //--------------------------------------------------------------------------
    task automatic wait_clks(input int n);
        repeat (n) @(posedge clk);
    endtask

    task automatic reset_dut;
        begin
            rst_n          = 1'b0;

            s_axil_awaddr  = '0;
            s_axil_awvalid = 1'b0;

            s_axil_wdata   = '0;
            s_axil_wstrb   = '0;
            s_axil_wvalid  = 1'b0;

            s_axil_bready  = 1'b0;

            s_axil_araddr  = '0;
            s_axil_arvalid = 1'b0;

            s_axil_rready  = 1'b0;

            spi_miso       = 1'b0;

            wait_clks(3);
            rst_n = 1'b1;
            wait_clks(2);
        end
    endtask

    task automatic expect_equal_u32(
        input string            label,
        input logic [31:0]      got,
        input logic [31:0]      exp
    );
        begin
            if (got !== exp) begin
                $error("%s FAILED: got=0x%08x exp=0x%08x", label, got, exp);
                $fatal(1);
            end
            else begin
                $display("[PASS] %s : 0x%08x", label, got);
            end
        end
    endtask

    task automatic expect_equal_u2(
        input string            label,
        input logic [1:0]       got,
        input logic [1:0]       exp
    );
        begin
            if (got !== exp) begin
                $error("%s FAILED: got=0b%b exp=0b%b", label, got, exp);
                $fatal(1);
            end
            else begin
                $display("[PASS] %s : 0b%b", label, got);
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // AXI-Lite write helpers
    //--------------------------------------------------------------------------
    task automatic axi_send_aw(input logic [ADDR_W-1:0] addr);
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1'b1;

            while (!(s_axil_awvalid && s_axil_awready)) begin
                @(posedge clk);
            end

            @(posedge clk);
            s_axil_awvalid <= 1'b0;
            s_axil_awaddr  <= '0;
        end
    endtask

    task automatic axi_send_w(
        input logic [DATA_W-1:0]         data,
        input logic [(DATA_W/8)-1:0]     strb
    );
        begin
            @(posedge clk);
            s_axil_wdata  <= data;
            s_axil_wstrb  <= strb;
            s_axil_wvalid <= 1'b1;

            while (!(s_axil_wvalid && s_axil_wready)) begin
                @(posedge clk);
            end

            @(posedge clk);
            s_axil_wvalid <= 1'b0;
            s_axil_wdata  <= '0;
            s_axil_wstrb  <= '0;
        end
    endtask

    task automatic axi_wait_b_and_check(input logic [1:0] exp_bresp);
        begin
            s_axil_bready <= 1'b1;

            while (!s_axil_bvalid) begin
                @(posedge clk);
            end

            expect_equal_u2("BRESP", s_axil_bresp, exp_bresp);

            @(posedge clk);
            s_axil_bready <= 1'b0;
        end
    endtask

    task automatic axi_write_aw_then_w(
        input logic [ADDR_W-1:0]         addr,
        input logic [DATA_W-1:0]         data,
        input logic [(DATA_W/8)-1:0]     strb,
        input logic [1:0]                exp_bresp
    );
        begin
            fork
                axi_send_aw(addr);
                begin
                    wait_clks(2);
                    axi_send_w(data, strb);
                end
            join

            axi_wait_b_and_check(exp_bresp);
        end
    endtask

    task automatic axi_write_w_then_aw(
        input logic [ADDR_W-1:0]         addr,
        input logic [DATA_W-1:0]         data,
        input logic [(DATA_W/8)-1:0]     strb,
        input logic [1:0]                exp_bresp
    );
        begin
            fork
                axi_send_w(data, strb);
                begin
                    wait_clks(2);
                    axi_send_aw(addr);
                end
            join

            axi_wait_b_and_check(exp_bresp);
        end
    endtask

    //--------------------------------------------------------------------------
    // AXI-Lite read helper
    //--------------------------------------------------------------------------
    task automatic axi_read(
        input  logic [ADDR_W-1:0]        addr,
        output logic [DATA_W-1:0]        data,
        output logic [1:0]               resp
    );
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arvalid <= 1'b1;

            while (!(s_axil_arvalid && s_axil_arready)) begin
                @(posedge clk);
            end

            @(posedge clk);
            s_axil_arvalid <= 1'b0;
            s_axil_araddr  <= '0;

            s_axil_rready <= 1'b1;
            while (!s_axil_rvalid) begin
                @(posedge clk);
            end

            data = s_axil_rdata;
            resp = s_axil_rresp;

            @(posedge clk);
            s_axil_rready <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // Tests
    //--------------------------------------------------------------------------
    logic [31:0] rd_data;
    logic [1:0]  rd_resp;

    initial begin
        $display("====================================================");
        $display("tb_axi_lite_spi starting");
        $display("====================================================");

        reset_dut();

        expect_equal_u32("reset rdata", s_axil_rdata, 32'h0000_0000);
        expect_equal_u2 ("reset bresp", s_axil_bresp, AXI_RESP_OKAY);
        expect_equal_u2 ("reset rresp", s_axil_rresp, AXI_RESP_OKAY);

        $display("\n[TEST] AW first, then W");
        axi_write_aw_then_w(12'h008, 32'hA5A5_1234, 4'hF, AXI_RESP_OKAY);

        $display("\n[TEST] Read back TXDATA");
        axi_read(12'h008, rd_data, rd_resp);
        expect_equal_u2 ("RRESP read TXDATA", rd_resp, AXI_RESP_OKAY);
        expect_equal_u32("RDATA read TXDATA", rd_data, 32'hA5A5_1234);

        $display("\n[TEST] W first, then AW");
        axi_write_w_then_aw(12'h010, 32'h0000_00AA, 4'hF, AXI_RESP_OKAY);

        $display("\n[TEST] Read back IRQ_EN");
        axi_read(12'h010, rd_data, rd_resp);
        expect_equal_u2 ("RRESP read IRQ_EN", rd_resp, AXI_RESP_OKAY);
        expect_equal_u32("RDATA read IRQ_EN", rd_data, 32'h0000_00AA);

        $display("\n[TEST] Write priority over read");
        fork
            begin
                axi_send_aw(12'h000);
            end
            begin
                wait_clks(1);
                axi_send_w(32'h0000_0001, 4'hF);
            end
            begin
                wait_clks(1);
                @(posedge clk);
                s_axil_araddr  <= 12'h004;
                s_axil_arvalid <= 1'b1;
                while (!(s_axil_arvalid && s_axil_arready)) begin
                    @(posedge clk);
                end
                @(posedge clk);
                s_axil_arvalid <= 1'b0;
                s_axil_araddr  <= '0;
            end
        join

        axi_wait_b_and_check(AXI_RESP_OKAY);

        s_axil_rready <= 1'b1;
        while (!s_axil_rvalid) begin
            @(posedge clk);
        end
        expect_equal_u2("RRESP status after write-priority test", s_axil_rresp, AXI_RESP_OKAY);
        @(posedge clk);
        s_axil_rready <= 1'b0;

        $display("\n[TEST] Bad write address -> SLVERR");
        axi_write_aw_then_w(12'h100, 32'hDEAD_BEEF, 4'hF, AXI_RESP_SLVERR);

        $display("\n[TEST] Bad read address -> SLVERR");
        axi_read(12'h104, rd_data, rd_resp);
        expect_equal_u2("RRESP bad read", rd_resp, AXI_RESP_SLVERR);

        $display("\n====================================================");
        $display("tb_axi_lite_spi PASSED");
        $display("====================================================");
        $finish;
    end

endmodule


//------------------------------------------------------------------------------
// Simple spi_regs stub for wrapper verification
//------------------------------------------------------------------------------
module spi_regs #(
    parameter int unsigned ADDR_W   = 12,
    parameter int unsigned DATA_W   = 32,
    parameter bit          CPOL     = 1'b0,
    parameter bit          CPHA     = 1'b1,
    parameter string       BITORDER = "MSB_FIRST",
    parameter int unsigned SPI_DW   = 8,
    parameter int unsigned CLKDIV   = 8
) (
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     req_valid,
    output logic                     req_ready,
    input  logic                     req_write,
    input  logic [ADDR_W-1:0]        req_addr,
    input  logic [DATA_W-1:0]        req_wdata,
    input  logic [(DATA_W/8)-1:0]    req_wstrb,

    output logic                     rsp_valid,
    input  logic                     rsp_ready,
    output logic [DATA_W-1:0]        rsp_rdata,
    output logic                     rsp_err,

    output logic                     irq,
    output logic                     spi_sclk,
    output logic                     spi_mosi,
    input  logic                     spi_miso,
    output logic                     spi_cs_n
);

    localparam logic [ADDR_W-1:0] REG_CTRL       = 12'h000;
    localparam logic [ADDR_W-1:0] REG_STATUS     = 12'h004;
    localparam logic [ADDR_W-1:0] REG_TXDATA     = 12'h008;
    localparam logic [ADDR_W-1:0] REG_RXDATA     = 12'h00C;
    localparam logic [ADDR_W-1:0] REG_IRQ_EN     = 12'h010;
    localparam logic [ADDR_W-1:0] REG_IRQ_STATUS = 12'h014;

    logic [31:0] reg_ctrl;
    logic [31:0] reg_status;
    logic [31:0] reg_txdata;
    logic [31:0] reg_rxdata;
    logic [31:0] reg_irq_en;
    logic [31:0] reg_irq_status;

    logic        busy_q;
    logic [1:0]  latency_cnt_q;

    logic        latched_write_q;
    logic [ADDR_W-1:0] latched_addr_q;
    logic [31:0] latched_wdata_q;
    logic [3:0]  latched_wstrb_q;

    assign req_ready = !busy_q && !rsp_valid;

    assign irq      = |(reg_irq_en & reg_irq_status);

    // Keep outputs alive and deterministic
    assign spi_sclk = CPOL ^ busy_q;
    assign spi_mosi = latched_wdata_q[0];
    assign spi_cs_n = !busy_q;

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_data,
        input logic [31:0] new_data,
        input logic [3:0]  wstrb
    );
        logic [31:0] result;
        begin
            result = old_data;
            if (wstrb[0]) result[7:0]   = new_data[7:0];
            if (wstrb[1]) result[15:8]  = new_data[15:8];
            if (wstrb[2]) result[23:16] = new_data[23:16];
            if (wstrb[3]) result[31:24] = new_data[31:24];
            return result;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl        <= '0;
            reg_status      <= 32'h0000_0008;
            reg_txdata      <= '0;
            reg_rxdata      <= 32'h1234_5678;
            reg_irq_en      <= '0;
            reg_irq_status  <= '0;

            busy_q          <= 1'b0;
            latency_cnt_q   <= '0;

            latched_write_q <= 1'b0;
            latched_addr_q  <= '0;
            latched_wdata_q <= '0;
            latched_wstrb_q <= '0;

            rsp_valid       <= 1'b0;
            rsp_rdata       <= '0;
            rsp_err         <= 1'b0;
        end
        else begin
            if (rsp_valid && rsp_ready) begin
                rsp_valid <= 1'b0;
                rsp_rdata <= '0;
                rsp_err   <= 1'b0;
            end

            if (req_valid && req_ready) begin
                busy_q          <= 1'b1;
                latency_cnt_q   <= 2'd2;
                latched_write_q <= req_write;
                latched_addr_q  <= req_addr;
                latched_wdata_q <= req_wdata;
                latched_wstrb_q <= req_wstrb;
            end
            else if (busy_q) begin
                if (latency_cnt_q != 0) begin
                    latency_cnt_q <= latency_cnt_q - 1'b1;
                end
                else begin
                    busy_q    <= 1'b0;
                    rsp_valid <= 1'b1;
                    rsp_err   <= 1'b0;
                    rsp_rdata <= '0;

                    unique case (latched_addr_q)
                        REG_CTRL: begin
                            if (latched_write_q) begin
                                reg_ctrl   <= apply_wstrb(reg_ctrl, latched_wdata_q, latched_wstrb_q);
                                reg_status <= 32'h0000_0018;
                            end
                            else begin
                                rsp_rdata <= reg_ctrl;
                            end
                        end

                        REG_STATUS: begin
                            if (latched_write_q) begin
                                rsp_err <= 1'b1;
                            end
                            else begin
                                rsp_rdata <= reg_status;
                            end
                        end

                        REG_TXDATA: begin
                            if (latched_write_q) begin
                                reg_txdata <= apply_wstrb(reg_txdata, latched_wdata_q, latched_wstrb_q);
                            end
                            else begin
                                rsp_rdata <= reg_txdata;
                            end
                        end

                        REG_RXDATA: begin
                            if (latched_write_q) begin
                                rsp_err <= 1'b1;
                            end
                            else begin
                                rsp_rdata <= reg_rxdata;
                            end
                        end

                        REG_IRQ_EN: begin
                            if (latched_write_q) begin
                                reg_irq_en <= apply_wstrb(reg_irq_en, latched_wdata_q, latched_wstrb_q);
                            end
                            else begin
                                rsp_rdata <= reg_irq_en;
                            end
                        end

                        REG_IRQ_STATUS: begin
                            if (latched_write_q) begin
                                reg_irq_status <= apply_wstrb(reg_irq_status, latched_wdata_q, latched_wstrb_q);
                            end
                            else begin
                                rsp_rdata <= reg_irq_status;
                            end
                        end

                        default: begin
                            rsp_err   <= 1'b1;
                            rsp_rdata <= 32'h0000_0000;
                        end
                    endcase
                end
            end
        end
    end

endmodule