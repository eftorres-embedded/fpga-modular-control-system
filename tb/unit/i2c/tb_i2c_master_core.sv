`timescale 1ns/1ps

module tb_i2c_master_core;

  localparam int unsigned DIVISOR_W = 16;
  localparam int unsigned BYTE_W    = 8;
  localparam int unsigned CMD_W     = 3;

  localparam logic [CMD_W-1:0] START_CMD   = 3'h0;
  localparam logic [CMD_W-1:0] WR_CMD      = 3'h1;
  localparam logic [CMD_W-1:0] RD_CMD      = 3'h2;
  localparam logic [CMD_W-1:0] STOP_CMD    = 3'h3;
  localparam logic [CMD_W-1:0] RESTART_CMD = 3'h4;

  // ------------------------------------------------------------
  // DUT interface signals
  // ------------------------------------------------------------
  logic                   clk;
  logic                   rst_n;

  logic [DIVISOR_W-1:0]   divisor;

  logic [BYTE_W-1:0]      rx_data_o;
  logic [BYTE_W-1:0]      tx_data_i;
  logic                   rd_last_i;

  logic                   sda_in;
  logic                   sda_out;

  logic                   scl_in;
  logic                   scl_out;

  logic [CMD_W-1:0]       cmd;
  logic                   cmd_illegal_o;
  logic                   cmd_valid_i;
  logic                   cmd_ready_o;

  logic                   done_tick_o;
  logic                   ack_o;
  logic                   ack_valid_o;
  logic                   rd_data_valid_o;

  logic                   bus_idle_o;
  logic                   master_receiving_o;

  // ------------------------------------------------------------
  // Open-drain bus model
  // ------------------------------------------------------------
  tri1 sda_bus;
  tri1 scl_bus;

  logic slave_sda_drive_low;

  // DUT-side wrapper behavior
  assign sda_bus = (master_receiving_o || sda_out) ? 1'bz : 1'b0;
  assign scl_bus = (scl_out) ? 1'bz : 1'b0;

  // Simple slave model: can only pull SDA low or release it
  assign sda_bus = slave_sda_drive_low ? 1'b0 : 1'bz;

  assign sda_in = sda_bus;
  assign scl_in = scl_bus;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  i2c_master #(
    .DIVISOR_W   (DIVISOR_W),
    .BYTE_W      (BYTE_W),
    .CMD_W       (CMD_W),
    .MIN_DIVISOR (16'd1)
  ) dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .divisor           (divisor),
    .rx_data_o         (rx_data_o),
    .tx_data_i         (tx_data_i),
    .rd_last_i         (rd_last_i),
    .sda_in            (sda_in),
    .sda_out           (sda_out),
    .scl_in            (scl_in),
    .scl_out           (scl_out),
    .cmd               (cmd),
    .cmd_illegal_o     (cmd_illegal_o),
    .cmd_valid_i       (cmd_valid_i),
    .cmd_ready_o       (cmd_ready_o),
    .done_tick_o       (done_tick_o),
    .ack_o             (ack_o),
    .ack_valid_o       (ack_valid_o),
    .rd_data_valid_o   (rd_data_valid_o),
    .bus_idle_o        (bus_idle_o),
    .master_receiving_o(master_receiving_o)
  );

  // ------------------------------------------------------------
  // Clock
  // ------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;  // 100 MHz

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  task automatic check(input bit cond, input string msg);
    if (!cond) begin
      $error("CHECK FAILED: %s", msg);
      $fatal(1);
    end
  endtask

  task automatic wait_cmd_ready;
    int i;
    for (i = 0; i < 2000; i++) begin
      if (cmd_ready_o === 1'b1)
        return;
      @(posedge clk);
    end
    $fatal(1, "Timeout waiting for cmd_ready_o");
  endtask

  task automatic wait_bus_idle;
    int i;
    for (i = 0; i < 2000; i++) begin
      if (bus_idle_o === 1'b1)
        return;
      @(posedge clk);
    end
    $fatal(1, "Timeout waiting for bus_idle_o");
  endtask

  task automatic wait_done_tick;
    int i;
    for (i = 0; i < 2000; i++) begin
      @(posedge clk or posedge done_tick_o);
      if (done_tick_o === 1'b1)
        return;
    end
    $fatal(1, "Timeout waiting for done_tick_o");
  endtask

  task automatic wait_rd_data_valid;
    int i;
    for (i = 0; i < 2000; i++) begin
      @(posedge clk or posedge rd_data_valid_o);
      if (rd_data_valid_o === 1'b1)
        return;
    end
    $fatal(1, "Timeout waiting for rd_data_valid_o");
  endtask

  task automatic issue_illegal_cmd_and_check(
  input logic [CMD_W-1:0]  cmd_i,
  input logic [BYTE_W-1:0] tx_i,
  input logic              rd_last_i_local,
  input string             msg
);
  @(negedge clk);
  cmd         <= cmd_i;
  tx_data_i   <= tx_i;
  rd_last_i   <= rd_last_i_local;
  cmd_valid_i <= 1'b1;

  // Check on the active edge where the DUT sees the command
  @(posedge clk);
  #1;
  check(cmd_illegal_o === 1'b1, msg);

  @(negedge clk);
  cmd_valid_i <= 1'b0;
  cmd         <= '0;
  tx_data_i   <= '0;
  rd_last_i   <= 1'b0;
endtask

  // Present one command for exactly one clock cycle, aligned so the DUT
  // sees stable inputs before the active clock edge.
  task automatic issue_cmd(
    input logic [CMD_W-1:0]  cmd_i,
    input logic [BYTE_W-1:0] tx_i,
    input logic              rd_last_i_local
  );
    wait_cmd_ready();

    @(negedge clk);
    cmd         <= cmd_i;
    tx_data_i   <= tx_i;
    rd_last_i   <= rd_last_i_local;
    cmd_valid_i <= 1'b1;

    @(negedge clk);
    cmd_valid_i <= 1'b0;
    cmd         <= '0;
    tx_data_i   <= '0;
    rd_last_i   <= 1'b0;
  endtask


  task automatic do_start;
    issue_cmd(START_CMD, '0, 1'b0);
    wait_cmd_ready();
    check(bus_idle_o == 1'b0, "bus_idle_o should deassert after START");
  endtask

  task automatic do_stop;
    issue_cmd(STOP_CMD, '0, 1'b0);
    wait_bus_idle();
    check(bus_idle_o == 1'b1, "bus_idle_o should assert after STOP");
  endtask

  // ack_bit = 0 means ACK, 1 means NACK
  task automatic slave_respond_ack(input bit ack_bit);
    // Wait until master releases SDA for write ACK phase
    wait (master_receiving_o === 1'b1 && scl_bus === 1'b0);

    // ACK -> drive low, NACK -> release
    slave_sda_drive_low <= (ack_bit == 1'b0);

    // Hold stable through SCL high sample point
    @(posedge scl_bus);
    @(negedge scl_bus);

    slave_sda_drive_low <= 1'b0;
  endtask

task automatic do_write(input logic [7:0] wr_byte, input bit ack_bit);
  fork
    slave_respond_ack(ack_bit);
    begin
      issue_cmd(WR_CMD, wr_byte, 1'b0);
      wait_done_tick();

      check(ack_valid_o === 1'b1, "ack_valid_o should pulse after WR_CMD");
      check(ack_o === ack_bit, "ack_o mismatch after WR_CMD");
    end
  join
endtask

  task automatic slave_send_read_byte(input logic [7:0] data_byte);
    integer i;

    // Wait for first read data bit setup window: master is receiving, SCL low
    wait (master_receiving_o === 1'b1 && scl_bus === 1'b0);

    for (i = BYTE_W-1; i >= 0; i--) begin
      // Drive current bit during SCL low so master samples it on SCL high
      slave_sda_drive_low <= ~data_byte[i];

      @(posedge scl_bus);  // master samples here

      if (i > 0)
        @(negedge scl_bus);
    end

    // After the last data bit, release SDA for master's ACK/NACK bit
    @(negedge scl_bus);
    slave_sda_drive_low <= 1'b0;
  endtask

  task automatic do_read_last_byte(
    input  logic [7:0] slave_byte,
    output logic [7:0] rx_byte
  );
    fork
      slave_send_read_byte(slave_byte);
      begin
        issue_cmd(RD_CMD, '0, 1'b1);  // last byte => master sends NACK
        wait_rd_data_valid();

        rx_byte = rx_data_o;

        check(rd_data_valid_o === 1'b1, "rd_data_valid_o should pulse after RD_CMD");
        check(rx_data_o === slave_byte, "rx_data_o mismatch after RD_CMD");
      end
    join
  endtask

  // ------------------------------------------------------------
  // Test sequence
  // ------------------------------------------------------------
  logic [7:0] rd_byte;

  initial begin
    // defaults
    rst_n               = 1'b0;
    divisor             = 16'd2;
    cmd                 = '0;
    cmd_valid_i         = 1'b0;
    tx_data_i           = '0;
    rd_last_i           = 1'b0;
    slave_sda_drive_low = 1'b0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    check(bus_idle_o === 1'b1, "bus_idle_o should be high after reset");
    check(cmd_ready_o === 1'b1, "cmd_ready_o should be high after reset");
    check(sda_bus === 1'b1, "SDA bus should be high after reset");
    check(scl_bus === 1'b1, "SCL bus should be high after reset");

 // Test 1: illegal WR in IDLE
$display("[TB] Test 1: illegal WR in IDLE");
issue_illegal_cmd_and_check(WR_CMD, 8'h55, 1'b0,
  "cmd_illegal_o should pulse for WR_CMD in IDLE");
check(bus_idle_o === 1'b1, "bus should remain idle after illegal WR in IDLE");

// Test 2: illegal START in HOLD
$display("[TB] Test 2: illegal START in HOLD");
do_start();
issue_illegal_cmd_and_check(START_CMD, 8'h00, 1'b0,
  "cmd_illegal_o should pulse for START_CMD in HOLD");
do_stop();

    // --------------------------------------------------------
    // Test 3: START -> WR(ACK) -> STOP
    // --------------------------------------------------------
    $display("[TB] Test 3: START -> WR(ACK) -> STOP");
    do_start();
    do_write(8'hA5, 1'b0);  // slave ACK
    do_stop();

    // --------------------------------------------------------
    // Test 4: START -> WR(NACK) -> STOP
    // --------------------------------------------------------
    $display("[TB] Test 4: START -> WR(NACK) -> STOP");
    do_start();
    do_write(8'h3C, 1'b1);  // slave NACK
    do_stop();

    // --------------------------------------------------------
    // Test 5: START -> WR(ACK) -> RESTART -> RD(last/NACK) -> STOP
    // --------------------------------------------------------
    $display("[TB] Test 5: START -> WR(ACK) -> RESTART -> RD(last/NACK) -> STOP");
    do_start();
    do_write(8'h68, 1'b0);               // some address/register byte, ACKed
    issue_cmd(RESTART_CMD, '0, 1'b0);
    wait_cmd_ready();
    do_read_last_byte(8'hD2, rd_byte);
    check(rd_byte == 8'hD2, "read-back byte mismatch");
    do_stop();

    $display("[TB] All tests passed.");
    repeat (10) @(posedge clk);
    $finish;
  end

endmodule