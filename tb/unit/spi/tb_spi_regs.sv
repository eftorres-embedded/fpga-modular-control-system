// tb_spi_regs.sv
// Testbench scaffold generated with assistance from ChatGPT (OpenAI)
// Modified and validated by Eder Torres

//This testbench is mainly validating the MMIO contract, sticky flags and IRQ

`timescale 1ns/1ps

module tb_spi_regs;

    localparam int unsigned ADDR_W = 12;
    localparam int unsigned DATA_W = 32;
    localparam int unsigned SPI_DW = 8;
    localparam int unsigned CLKDIV = 8;

    // ------------------------------------------------------------
    // MMIO register offsets
    // ------------------------------------------------------------
    localparam logic [ADDR_W-1:0] REG_CTRL       = 'h000;
    localparam logic [ADDR_W-1:0] REG_STATUS     = 'h004;
    localparam logic [ADDR_W-1:0] REG_TXDATA     = 'h008;
    localparam logic [ADDR_W-1:0] REG_RXDATA     = 'h00C;
    localparam logic [ADDR_W-1:0] REG_IRQ_EN     = 'h010;
    localparam logic [ADDR_W-1:0] REG_IRQ_STATUS = 'h014;

    // ------------------------------------------------------------
    // CTRL bits
    // ------------------------------------------------------------
    localparam int CTRL_ENABLE_BIT       = 0;
    localparam int CTRL_START_BIT        = 1;
    localparam int CTRL_XFER_END_BIT     = 2;
    localparam int CTRL_CLR_DONE_BIT     = 3;
    localparam int CTRL_CLR_RX_VALID_BIT = 4;

    // ------------------------------------------------------------
    // STATUS bits
    // ------------------------------------------------------------
    localparam int STATUS_BUSY_BIT      = 0;
    localparam int STATUS_DONE_BIT      = 1;
    localparam int STATUS_RX_VALID_BIT  = 2;
    localparam int STATUS_TX_READY_BIT  = 3;
    localparam int STATUS_ENABLED_BIT   = 4;
    localparam int STATUS_CS_ACTIVE_BIT = 5;

    // ------------------------------------------------------------
    // IRQ bits
    // ------------------------------------------------------------
    localparam int IRQ_DONE_BIT     = 0;
    localparam int IRQ_RX_VALID_BIT = 1;

    // ------------------------------------------------------------
    // DUT interface signals
    // ------------------------------------------------------------
    logic                     clk;
    logic                     rst_n;

    logic                     req_valid;
    logic                     req_ready;
    logic                     req_write;
    logic [ADDR_W-1:0]        req_addr;
    logic [DATA_W-1:0]        req_wdata;
    logic [(DATA_W/8)-1:0]    req_wstrb;

    logic                     rsp_valid;
    logic                     rsp_ready;
    logic [DATA_W-1:0]        rsp_rdata;
    logic                     rsp_err;

    logic                     irq;

    logic                     spi_sclk;
    logic                     spi_mosi;
    logic                     spi_miso;
    logic                     spi_cs_n;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    spi_regs #(
        .ADDR_W   (ADDR_W),
        .DATA_W   (DATA_W),
        .CPOL     (1'b0),
        .CPHA     (1'b1),
        .BITORDER ("MSB_FIRST"),
        .SPI_DW   (SPI_DW),
        .CLKDIV   (CLKDIV)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),

        .req_valid  (req_valid),
        .req_ready  (req_ready),
        .req_write  (req_write),
        .req_addr   (req_addr),
        .req_wdata  (req_wdata),
        .req_wstrb  (req_wstrb),

        .rsp_valid  (rsp_valid),
        .rsp_ready  (rsp_ready),
        .rsp_rdata  (rsp_rdata),
        .rsp_err    (rsp_err),

        .irq        (irq),

        .spi_sclk   (spi_sclk),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso),
        .spi_cs_n   (spi_cs_n)
    );

    // ------------------------------------------------------------
    // Simple loopback
    // ------------------------------------------------------------
    // For a smoke test, tie MISO to MOSI.
    // Depending on the vendor core’s exact sampling/launch behavior and CPHA,
    // RXDATA may or may not exactly equal TXDATA in this simple setup.
    // The testbench therefore treats RXDATA comparison as informational.
    assign spi_miso = spi_mosi;

    // ------------------------------------------------------------
    // Clock generation
    // ------------------------------------------------------------
    initial clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz

    // ------------------------------------------------------------
    // Helper variables
    // ------------------------------------------------------------
    logic [DATA_W-1:0] rd_data;
    int timeout_count;

    // ------------------------------------------------------------
    // MMIO tasks
    // ------------------------------------------------------------
    task automatic mmio_write(
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] data
    );
    begin
        @(posedge clk);
        req_valid <= 1'b1;
        req_write <= 1'b1;
        req_addr  <= addr;
        req_wdata <= data;
        req_wstrb <= '1;

        // Wait until request accepted
        while (!(req_valid && req_ready)) begin
            @(posedge clk);
        end

        // Drop request after acceptance
        @(posedge clk);
        req_valid <= 1'b0;
        req_write <= 1'b0;
        req_addr  <= '0;
        req_wdata <= '0;
        req_wstrb <= '0;

        // Wait for response
        while (!rsp_valid) begin
            @(posedge clk);
        end

        if (rsp_err) begin
            $error("MMIO WRITE ERROR at addr 0x%0h", addr);
            $fatal;
        end

        // Response consumed automatically because rsp_ready=1
        @(posedge clk);
    end
    endtask

    task automatic mmio_read(
        input  logic [ADDR_W-1:0] addr,
        output logic [DATA_W-1:0] data
    );
    begin
        @(posedge clk);
        req_valid <= 1'b1;
        req_write <= 1'b0;
        req_addr  <= addr;
        req_wdata <= '0;
        req_wstrb <= '0;

        // Wait until request accepted
        while (!(req_valid && req_ready)) begin
            @(posedge clk);
        end

        // Drop request after acceptance
        @(posedge clk);
        req_valid <= 1'b0;
        req_write <= 1'b0;
        req_addr  <= '0;

        // Wait for response
        while (!rsp_valid) begin
            @(posedge clk);
        end

        if (rsp_err) begin
            $error("MMIO READ ERROR at addr 0x%0h", addr);
            $fatal;
        end

        data = rsp_rdata;

        // Response consumed automatically because rsp_ready=1
        @(posedge clk);
    end
    endtask

    task automatic print_status(input logic [DATA_W-1:0] status_word);
    begin
        $display("STATUS = 0x%08h | busy=%0d done=%0d rx_valid=%0d tx_ready=%0d enabled=%0d cs_active=%0d",
                 status_word,
                 status_word[STATUS_BUSY_BIT],
                 status_word[STATUS_DONE_BIT],
                 status_word[STATUS_RX_VALID_BIT],
                 status_word[STATUS_TX_READY_BIT],
                 status_word[STATUS_ENABLED_BIT],
                 status_word[STATUS_CS_ACTIVE_BIT]);
    end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    initial begin
        // Defaults
        rst_n      = 1'b0;
        req_valid  = 1'b0;
        req_write  = 1'b0;
        req_addr   = '0;
        req_wdata  = '0;
        req_wstrb  = '0;
        rsp_ready  = 1'b1;

        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("--------------------------------------------------");
        $display("tb_spi_regs: starting smoke test");
        $display("--------------------------------------------------");

        // Read initial status
        mmio_read(REG_STATUS, rd_data);
        print_status(rd_data);

        // Enable DONE and RX_VALID interrupts
        mmio_write(REG_IRQ_EN, (1 << IRQ_DONE_BIT) | (1 << IRQ_RX_VALID_BIT));

        // Load TX byte
        mmio_write(REG_TXDATA, 32'h000000A5);

        // Enable peripheral and keep XFER_END = 1 for one-word transaction
        mmio_write(REG_CTRL, (1 << CTRL_ENABLE_BIT) | (1 << CTRL_XFER_END_BIT));

        // Start transfer
        mmio_write(REG_CTRL,
            (1 << CTRL_ENABLE_BIT)   |
            (1 << CTRL_XFER_END_BIT) |
            (1 << CTRL_START_BIT)
        );

        // Poll until DONE
        timeout_count = 0;
        while (1) begin
            mmio_read(REG_STATUS, rd_data);

            if (timeout_count == 0 || (timeout_count % 10) == 0) begin
                print_status(rd_data);
            end

            if (rd_data[STATUS_DONE_BIT]) begin
                break;
            end

            timeout_count++;
            if (timeout_count > 500) begin
                $error("Timeout waiting for STATUS.DONE");
                $fatal;
            end
        end

        $display("Transfer completed after %0d polls.", timeout_count);

        // Check sticky status bits
        if (!rd_data[STATUS_RX_VALID_BIT]) begin
            $error("Expected STATUS.RX_VALID=1 after transfer");
            $fatal;
        end

        // Check IRQ asserted
        if (!irq) begin
            $error("Expected irq=1 after enabled pending events");
            $fatal;
        end

        // Read RXDATA
        mmio_read(REG_RXDATA, rd_data);
        $display("RXDATA = 0x%02h", rd_data[7:0]);

        // Read IRQ_STATUS
        mmio_read(REG_IRQ_STATUS, rd_data);
        $display("IRQ_STATUS = 0x%08h", rd_data);

        if (!rd_data[IRQ_DONE_BIT]) begin
            $error("Expected IRQ_STATUS.DONE_IP=1");
            $fatal;
        end

        if (!rd_data[IRQ_RX_VALID_BIT]) begin
            $error("Expected IRQ_STATUS.RX_VALID_IP=1");
            $fatal;
        end

        // Clear IRQ pending bits
        mmio_write(REG_IRQ_STATUS, (1 << IRQ_DONE_BIT) | (1 << IRQ_RX_VALID_BIT));

        // Clear sticky status bits
        mmio_write(REG_CTRL, (1 << CTRL_CLR_DONE_BIT) | (1 << CTRL_CLR_RX_VALID_BIT));

        // Confirm IRQ deasserted
        @(posedge clk);
        if (irq) begin
            $error("Expected irq=0 after clearing pending bits");
            $fatal;
        end

        // Confirm sticky flags cleared
        mmio_read(REG_STATUS, rd_data);
        print_status(rd_data);

        if (rd_data[STATUS_DONE_BIT]) begin
            $error("Expected STATUS.DONE=0 after CLR_DONE");
            $fatal;
        end

        if (rd_data[STATUS_RX_VALID_BIT]) begin
            $error("Expected STATUS.RX_VALID=0 after CLR_RX_VALID");
            $fatal;
        end

        $display("--------------------------------------------------");
        $display("tb_spi_regs: PASS");
        $display("--------------------------------------------------");

        #100;
        $finish;
    end

endmodule