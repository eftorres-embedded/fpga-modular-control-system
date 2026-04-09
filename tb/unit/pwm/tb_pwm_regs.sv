// tb_pwm_regs_v2.sv
//
// Focus of this testbench:
// - reset defaults
// - MMIO read/write behavior
// - REG_DUTY[i] bank decode
// - shadow vs active separation
// - REG_APPLY immediate mode (APPLY_ON_PERIOD_END = 0)
// - REG_CH_ENABLE / REG_POLARITY / REG_MOTOR_CTRL
//
// Notes:
// - This TB targets pwm_regs only, not the whole PWM subsystem.
// - period_end_i and cnt_i are driven manually here.
// - Start with APPLY_ON_PERIOD_END=0 to validate the V2 banked register model
//   before adding deferred/boundary-sync behavior.

`timescale 1ns/1ps

module tb_pwm_regs;

    localparam int unsigned ADDR_W   = 12;
    localparam int unsigned DATA_W   = 32;
    localparam int unsigned CNT_W    = 32;
    localparam int unsigned CHANNELS = 4;

    // Register offsets
    localparam logic [ADDR_W-1:0] REG_CTRL       = 'h00;
    localparam logic [ADDR_W-1:0] REG_PERIOD     = 'h04;
    localparam logic [ADDR_W-1:0] REG_APPLY      = 'h08;
    localparam logic [ADDR_W-1:0] REG_CH_ENABLE  = 'h0C;
    localparam logic [ADDR_W-1:0] REG_STATUS     = 'h10;
    localparam logic [ADDR_W-1:0] REG_CNT        = 'h14;
    localparam logic [ADDR_W-1:0] REG_POLARITY   = 'h18;
    localparam logic [ADDR_W-1:0] REG_MOTOR_CTRL = 'h1C;
    localparam logic [ADDR_W-1:0] REG_DUTY_BASE  = 'h20;

    // Clock / reset
    logic clk;
    logic rst_n;

    // MMIO request channel
    logic                    req_valid;
    logic                    req_ready;
    logic                    req_write;
    logic [ADDR_W-1:0]       req_addr;
    logic [DATA_W-1:0]       req_wdata;
    logic [(DATA_W/8)-1:0]   req_wstrb;

    // MMIO response channel
    logic                    rsp_valid;
    logic                    rsp_ready;
    logic [DATA_W-1:0]       rsp_rdata;
    logic                    rsp_err;

    // Core-side status inputs
    logic                    period_end_i;
    logic [CNT_W-1:0]        cnt_i;

    // Core-side active outputs
    logic                    enable_o;
    logic [CHANNELS-1:0]     ch_enable_o;
    logic [CNT_W-1:0]        period_cycles_o;
    logic [CNT_W-1:0]        duty_cycles_o [CHANNELS];

    // Placeholder outputs
    logic [CHANNELS-1:0]     polarity_o;
    logic [DATA_W-1:0]       motor_ctrl_o;

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    pwm_regs #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .CNT_W(CNT_W),
        .CHANNELS(CHANNELS),
        .APPLY_ON_PERIOD_END(1'b0)   // immediate mode first
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_wdata(req_wdata),
        .req_wstrb(req_wstrb),

        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_rdata(rsp_rdata),
        .rsp_err(rsp_err),

        .period_end_i(period_end_i),
        .cnt_i(cnt_i),

        .enable_o(enable_o),
        .ch_enable_o(ch_enable_o),
        .period_cycles_o(period_cycles_o),
        .duty_cycles_o(duty_cycles_o),

        .polarity_o(polarity_o),
        .motor_ctrl_o(motor_ctrl_o)
    );

    //--------------------------------------------------------------------------
    // Clock
    //--------------------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    //--------------------------------------------------------------------------
    // Simple MMIO driver tasks
    //--------------------------------------------------------------------------
    task automatic mmio_write(
        input logic [ADDR_W-1:0]      addr,
        input logic [DATA_W-1:0]      data,
        input logic [(DATA_W/8)-1:0]  strb = '1
    );
    begin
        // Drive request
        @(posedge clk);
        req_valid <= 1'b1;
        req_write <= 1'b1;
        req_addr  <= addr;
        req_wdata <= data;
        req_wstrb <= strb;

        // Wait until request is accepted
        while (!(req_valid && req_ready))
            @(posedge clk);

        // Drop request on next edge
        @(posedge clk);
        req_valid <= 1'b0;
        req_write <= 1'b0;
        req_addr  <= '0;
        req_wdata <= '0;
        req_wstrb <= '0;

        // Wait for response
        while (!rsp_valid)
            @(posedge clk);

        // Response consumed immediately (rsp_ready kept high)
        if (rsp_err) begin
            $error("MMIO WRITE error response at addr 0x%0h", addr);
        end
    end
    endtask

    task automatic mmio_read(
        input  logic [ADDR_W-1:0] addr,
        output logic [DATA_W-1:0] data
    );
    begin
        // Drive request
        @(posedge clk);
        req_valid <= 1'b1;
        req_write <= 1'b0;
        req_addr  <= addr;
        req_wdata <= '0;
        req_wstrb <= '0;

        // Wait until request is accepted
        while (!(req_valid && req_ready))
            @(posedge clk);

        // Drop request on next edge
        @(posedge clk);
        req_valid <= 1'b0;
        req_addr  <= '0;

        // Wait for response
        while (!rsp_valid)
            @(posedge clk);

        data = rsp_rdata;

        if (rsp_err) begin
            $error("MMIO READ error response at addr 0x%0h", addr);
        end
    end
    endtask

    //--------------------------------------------------------------------------
    // Simple check helpers
    //--------------------------------------------------------------------------
    task automatic expect_eq(
        input string            name,
        input logic [31:0]      got,
        input logic [31:0]      exp
    );
    begin
        if (got !== exp) begin
            $error("%s mismatch. got=0x%08h exp=0x%08h", name, got, exp);
        end
        else begin
            $display("[PASS] %s = 0x%08h", name, got);
        end
    end
    endtask

    task automatic expect_bitvec(
        input string                    name,
        input logic [CHANNELS-1:0]      got,
        input logic [CHANNELS-1:0]      exp
    );
    begin
        if (got !== exp) begin
            $error("%s mismatch. got=0x%0h exp=0x%0h", name, got, exp);
        end
        else begin
            $display("[PASS] %s = 0x%0h", name, got);
        end
    end
    endtask

    //--------------------------------------------------------------------------
    // Test sequence
    //--------------------------------------------------------------------------
    logic [DATA_W-1:0] rd_data;
    integer i;

    initial begin
        // Default drives
        rst_n       = 1'b0;

        req_valid   = 1'b0;
        req_write   = 1'b0;
        req_addr    = '0;
        req_wdata   = '0;
        req_wstrb   = '0;

        rsp_ready   = 1'b1;

        period_end_i = 1'b0;
        cnt_i        = '0;

        //----------------------------------------------------------------------
        // Reset
        //----------------------------------------------------------------------
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("--------------------------------------------------");
        $display("T1: Reset defaults");
        $display("--------------------------------------------------");

        // Active outputs should reset low/zero
        expect_eq("enable_o after reset", enable_o, 32'd0);
        expect_bitvec("ch_enable_o after reset", ch_enable_o, '0);
        expect_eq("period_cycles_o after reset", period_cycles_o, 32'd0);
        expect_bitvec("polarity_o after reset", polarity_o, '0);
        expect_eq("motor_ctrl_o after reset", motor_ctrl_o, 32'd0);

        for (i = 0; i < CHANNELS; i++) begin
            expect_eq($sformatf("duty_cycles_o[%0d] after reset", i), duty_cycles_o[i], 32'd0);
        end

        //----------------------------------------------------------------------
        // Read shadow defaults
        //----------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("T2: Read reset shadow registers");
        $display("--------------------------------------------------");

        mmio_read(REG_CTRL, rd_data);
        expect_eq("REG_CTRL reset", rd_data, 32'd0);

        mmio_read(REG_PERIOD, rd_data);
        expect_eq("REG_PERIOD reset", rd_data, 32'd0);

        mmio_read(REG_CH_ENABLE, rd_data);
        expect_eq("REG_CH_ENABLE reset", rd_data, 32'd0);

        mmio_read(REG_POLARITY, rd_data);
        expect_eq("REG_POLARITY reset", rd_data, 32'd0);

        mmio_read(REG_MOTOR_CTRL, rd_data);
        expect_eq("REG_MOTOR_CTRL reset", rd_data, 32'd0);

        for (i = 0; i < CHANNELS; i++) begin
            mmio_read(REG_DUTY_BASE + i*4, rd_data);
            expect_eq($sformatf("REG_DUTY[%0d] reset", i), rd_data, 32'd0);
        end

        //----------------------------------------------------------------------
        // Program shadow registers only, verify active outputs do not change yet
        //----------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("T3: Shadow write only, before APPLY");
        $display("--------------------------------------------------");

        mmio_write(REG_CTRL,       32'h0000_0001); // global enable shadow
        mmio_write(REG_PERIOD,     32'd100);
        mmio_write(REG_CH_ENABLE,  32'h0000_000B); // channels 0,1,3 enabled
        mmio_write(REG_POLARITY,   32'h0000_0005); // placeholder only
        mmio_write(REG_MOTOR_CTRL, 32'h1234_5678);

        mmio_write(REG_DUTY_BASE + 0*4, 32'd10);
        mmio_write(REG_DUTY_BASE + 1*4, 32'd20);
        mmio_write(REG_DUTY_BASE + 2*4, 32'd30);
        mmio_write(REG_DUTY_BASE + 3*4, 32'd40);

        // Readback should reflect SHADOW values
        mmio_read(REG_CTRL, rd_data);
        expect_eq("REG_CTRL shadow", rd_data, 32'h0000_0001);

        mmio_read(REG_PERIOD, rd_data);
        expect_eq("REG_PERIOD shadow", rd_data, 32'd100);

        mmio_read(REG_CH_ENABLE, rd_data);
        expect_eq("REG_CH_ENABLE shadow", rd_data, 32'h0000_000B);

        mmio_read(REG_POLARITY, rd_data);
        expect_eq("REG_POLARITY shadow", rd_data, 32'h0000_0005);

        mmio_read(REG_MOTOR_CTRL, rd_data);
        expect_eq("REG_MOTOR_CTRL shadow", rd_data, 32'h1234_5678);

        // But active outputs should still be unchanged before APPLY
        expect_eq("enable_o before APPLY", enable_o, 32'd0);
        expect_bitvec("ch_enable_o before APPLY", ch_enable_o, '0);
        expect_eq("period_cycles_o before APPLY", period_cycles_o, 32'd0);

        for (i = 0; i < CHANNELS; i++) begin
            expect_eq($sformatf("duty_cycles_o[%0d] before APPLY", i), duty_cycles_o[i], 32'd0);
        end

        //----------------------------------------------------------------------
        // Apply immediately
        //----------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("T4: APPLY immediate mode");
        $display("--------------------------------------------------");

        mmio_write(REG_APPLY, 32'h0000_0001);

        // Active outputs should now reflect shadow state
        expect_eq("enable_o after APPLY", enable_o, 32'd1);
        expect_bitvec("ch_enable_o after APPLY", ch_enable_o, 4'b1011);
        expect_eq("period_cycles_o after APPLY", period_cycles_o, 32'd100);
        expect_bitvec("polarity_o after APPLY", polarity_o, 4'b0101);
        expect_eq("motor_ctrl_o after APPLY", motor_ctrl_o, 32'h1234_5678);

        expect_eq("duty_cycles_o[0] after APPLY", duty_cycles_o[0], 32'd10);
        expect_eq("duty_cycles_o[1] after APPLY", duty_cycles_o[1], 32'd20);
        expect_eq("duty_cycles_o[2] after APPLY", duty_cycles_o[2], 32'd30);
        expect_eq("duty_cycles_o[3] after APPLY", duty_cycles_o[3], 32'd40);

        //----------------------------------------------------------------------
        // STATUS / CNT readback
        //----------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("T5: REG_STATUS and REG_CNT");
        $display("--------------------------------------------------");

        cnt_i        = 32'h0000_0033;
        period_end_i = 1'b1;
        @(posedge clk);
        mmio_read(REG_STATUS, rd_data);
        // bit0 = period_end_i, bit1 = apply_pending, bit2 = active global enable
        expect_eq("REG_STATUS", rd_data[2:0], 3'b101);

        mmio_read(REG_CNT, rd_data);
        expect_eq("REG_CNT", rd_data, 32'h0000_0033);

        period_end_i = 1'b0;

        //----------------------------------------------------------------------
        // Partial-byte write sanity on REG_CH_ENABLE
        //----------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("T6: Partial-byte write sanity");
        $display("--------------------------------------------------");

        // Lower byte write only
        mmio_write(REG_CH_ENABLE, 32'h0000_0006, 4'b0001);
        mmio_read(REG_CH_ENABLE, rd_data);
        expect_eq("REG_CH_ENABLE shadow after partial write", rd_data, 32'h0000_0006);

        mmio_write(REG_APPLY, 32'h0000_0001);
        expect_bitvec("ch_enable_o after partial write APPLY", ch_enable_o, 4'b0110);

        //----------------------------------------------------------------------
        // Invalid duty address should error on read
        //----------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("T7: Invalid address decode");
        $display("--------------------------------------------------");

        @(posedge clk);
        req_valid <= 1'b1;
        req_write <= 1'b0;
        req_addr  <= REG_DUTY_BASE + CHANNELS*4; // first invalid duty address
        req_wdata <= '0;
        req_wstrb <= '0;

        while (!(req_valid && req_ready))
            @(posedge clk);

        @(posedge clk);
        req_valid <= 1'b0;
        req_addr  <= '0;

        while (!rsp_valid)
            @(posedge clk);

        if (!rsp_err) begin
            $error("Expected decode error on invalid duty address read");
        end
        else begin
            $display("[PASS] Invalid duty address read returned rsp_err=1");
        end

        //----------------------------------------------------------------------
        // Done
        //----------------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("tb_pwm_regs_v2 completed");
        $display("--------------------------------------------------");
        repeat (3) @(posedge clk);
        $finish;
    end

endmodule