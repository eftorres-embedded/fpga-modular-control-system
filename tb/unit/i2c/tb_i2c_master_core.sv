`timescale 1ns / 1ps

module tb_i2c_master_core;

    localparam int DIVISOR_W = 16;
    localparam int DATA_W    = 9;
    localparam int CMD_W     = 3;

    localparam logic [CMD_W-1:0] START_CMD   = 3'h0;
    localparam logic [CMD_W-1:0] WR_CMD      = 3'h1;
    localparam logic [CMD_W-1:0] RD_CMD      = 3'h2;
    localparam logic [CMD_W-1:0] STOP_CMD    = 3'h3;
    localparam logic [CMD_W-1:0] RESTART_CMD = 3'h4;

    logic clk;
    logic rst_n;

    logic [DIVISOR_W-1:0] divisor;
    logic                 ready;
    logic                 ack;
    logic                 done_tick;

    logic [DATA_W-2:0]    rx_data_o;
    logic [DATA_W-2:0]    tx_data_i;

    logic                 sda_in;
    logic                 sda_out;
    logic                 scl_in;
    logic                 scl_out;

    logic [CMD_W-1:0]     cmd;
    logic                 wr_i2c;
    logic                 master_receiving;

    tri1 sda_line;
    tri1 scl_line;

    logic slave_drive_low;
    logic [7:0] slave_read_byte;

    assign sda_line = (master_receiving || sda_out) ? 1'bz : 1'b0;
    assign scl_line = scl_out ? 1'bz : 1'b0;
    assign sda_line = slave_drive_low ? 1'b0 : 1'bz;

    assign sda_in = sda_line;
    assign scl_in = scl_line;

    always_comb begin
        slave_drive_low = 1'b0;

        if (master_receiving) begin
            if (cmd == WR_CMD && dut.bit_idx_reg == 8) begin
                slave_drive_low = 1'b1; // ACK = 0 on bus
            end else if (cmd == RD_CMD && dut.bit_idx_reg < 8) begin
                slave_drive_low = ~slave_read_byte[7 - dut.bit_idx_reg];
            end
        end
    end

    i2c_master #(
        .DIVISOR_W (DIVISOR_W),
        .DATA_W    (DATA_W),
        .CMD_W     (CMD_W)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .divisor          (divisor),
        .ready            (ready),
        .ack              (ack),
        .done_tick        (done_tick),
        .rx_data_o        (rx_data_o),
        .tx_data_i        (tx_data_i),
        .sda_in           (sda_in),
        .sda_out          (sda_out),
        .scl_in           (scl_in),
        .scl_out          (scl_out),
        .cmd              (cmd),
        .wr_i2c           (wr_i2c),
        .master_receiving (master_receiving)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    task automatic pulse_cmd(
        input logic [CMD_W-1:0] c,
        input logic [7:0]       tx_byte
    );
    begin
        @(negedge clk);
        cmd       <= c;
        tx_data_i <= tx_byte;
        wr_i2c    <= 1'b1;

        @(negedge clk);
        wr_i2c    <= 1'b0;
    end
    endtask

    task automatic wait_ready;
        integer i;
        logic found;
    begin
        found = 1'b0;
        for (i = 0; i < 10000; i = i + 1) begin
            @(posedge clk);
            if (ready) begin
                found = 1'b1;
                i = 10000;
            end
        end
        if (!found) begin
            $fatal(1, "Timeout waiting for ready");
        end
    end
    endtask

    task automatic wait_done_tick;
        integer i;
        logic found;
    begin
        found = 1'b0;
        for (i = 0; i < 10000; i = i + 1) begin
            @(posedge clk);
            if (done_tick) begin
                found = 1'b1;
                i = 10000;
            end
        end
        if (!found) begin
            $fatal(1, "Timeout waiting for done_tick");
        end
    end
    endtask

    initial begin
        rst_n           = 1'b0;
        divisor         = 16'd4;
        tx_data_i       = '0;
        cmd             = START_CMD;
        wr_i2c          = 1'b0;
        slave_read_byte = 8'hA5;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("TB: Reset released");

        if (scl_line !== 1'b1 || sda_line !== 1'b1) begin
            $fatal(1, "Idle bus not high after reset");
        end

        $display("TB: START");
        pulse_cmd(START_CMD, 8'h00);
        wait_ready();

        $display("TB: WR 0xD0");
        pulse_cmd(WR_CMD, 8'hD0);
        wait_done_tick();

        if (ack !== 1'b0) begin
            $display("TB WARN: expected raw ACK bit 0 after write, got ack=%b", ack);
        end

        $display("TB: RESTART");
        pulse_cmd(RESTART_CMD, 8'h00);
        wait_ready();

        $display("TB: RD expecting 0xA5");
        pulse_cmd(RD_CMD, 8'h01);
        wait_done_tick();

        $display("TB: rx_data_o = 0x%02h", rx_data_o);
        if (rx_data_o !== 8'hA5) begin
            $display("TB WARN: expected 0xA5 from slave model, got 0x%02h", rx_data_o);
        end

        $display("TB: STOP");
        pulse_cmd(STOP_CMD, 8'h00);

        repeat (20) @(posedge clk);

        if (scl_line !== 1'b1) begin
            $display("TB WARN: SCL not released high at end");
        end

        $display("TB: completed");
        $finish;
    end

endmodule
