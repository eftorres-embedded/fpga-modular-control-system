`timescale 1ns/1ps

module tb_i2c_regs;

  localparam int ADDR_W          = 12;
  localparam int DATA_W          = 32;
  localparam int BYTE_W          = 8;
  localparam int CMD_W           = 3;
  localparam int DIVISOR_W       = 16;
  localparam int CLK_PERIOD      = 10;
  localparam int TIMEOUT_CYCLES  = 5000;

  localparam logic [ADDR_W-1:0] REG_STATUS   = 12'h000;
  localparam logic [ADDR_W-1:0] REG_DIVISOR  = 12'h004;
  localparam logic [ADDR_W-1:0] REG_TXDATA   = 12'h008;
  localparam logic [ADDR_W-1:0] REG_RXDATA   = 12'h00C;
  localparam logic [ADDR_W-1:0] REG_CMD      = 12'h010;

  localparam logic [CMD_W-1:0] START_CMD     = 3'h0;
  localparam logic [CMD_W-1:0] WR_CMD        = 3'h1;
  localparam logic [CMD_W-1:0] RD_CMD        = 3'h2;
  localparam logic [CMD_W-1:0] STOP_CMD      = 3'h3;
  localparam logic [CMD_W-1:0] RESTART_CMD   = 3'h4;

  localparam int STATUS_CMD_READY        = 0;
  localparam int STATUS_BUS_IDLE         = 1;
  localparam int STATUS_DONE_TICK        = 2;
  localparam int STATUS_ACK_VALID        = 3;
  localparam int STATUS_ACK              = 4;
  localparam int STATUS_RD_DATA_VALID    = 5;
  localparam int STATUS_CMD_ILLEGAL      = 6;
  localparam int STATUS_MASTER_RECEIVING = 7;

  logic                       clk;
  logic                       rst_n;

  logic                       req_valid;
  logic                       req_ready;
  logic                       req_write;
  logic   [ADDR_W-1:0]        req_addr;
  logic   [DATA_W-1:0]        req_wdata;
  logic   [(DATA_W/8)-1:0]    req_wstrb;

  logic                       rsp_valid;
  logic                       rsp_ready;
  logic   [DATA_W-1:0]        rsp_rdata;
  logic                       rsp_err;

  tri1 sda_line;
  tri1 scl_line;

  logic sda_in;
  logic sda_out;
  logic scl_in;
  logic scl_out;
  logic master_receiving_o;

  logic slave_sda_drive_low;

  logic [DATA_W-1:0] rd_data;
  logic master_ack_low;
  logic master_ack_low_last;

  // --------------------------------------------------------------------------
  // Open-drain bus model
  // --------------------------------------------------------------------------
  assign sda_line = ((master_receiving_o || sda_out) ? 1'bz : 1'b0);
  assign sda_line = (slave_sda_drive_low ? 1'b0 : 1'bz);
  assign scl_line = (scl_out ? 1'bz : 1'b0);

  assign sda_in = sda_line;
  assign scl_in = scl_line;

  i2c_regs #(
    .ADDR_W      (ADDR_W),
    .DATA_W      (DATA_W),
    .BYTE_W      (BYTE_W),
    .CMD_W       (CMD_W),
    .DIVISOR_W   (DIVISOR_W),
    .MIN_DIVISOR (16'd2)
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

  // --------------------------------------------------------------------------
  // Clock / reset
  // --------------------------------------------------------------------------
  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // --------------------------------------------------------------------------
  // Timeout helpers
  // --------------------------------------------------------------------------
  task automatic wait_req_ready(input logic [ADDR_W-1:0] addr);
    int cycles;
    begin
      cycles = 0;
      while (req_ready !== 1'b1) begin
        @(posedge clk);
        cycles++;
        if (cycles > TIMEOUT_CYCLES) begin
          $fatal(1, "Timeout waiting for req_ready at addr 0x%0h", addr);
        end
      end
    end
  endtask

  task automatic wait_rsp_valid(input logic [ADDR_W-1:0] addr);
    int cycles;
    begin
      cycles = 0;
      while (rsp_valid !== 1'b1) begin
        @(posedge clk);
        cycles++;
        if (cycles > TIMEOUT_CYCLES) begin
          $fatal(1, "Timeout waiting for rsp_valid at addr 0x%0h", addr);
        end
      end
    end
  endtask

  task automatic wait_cmd_ready_in_hold;
    int cycles;
    begin
      cycles = 0;
      while (!(dut.i2c_cmd_ready === 1'b1 && dut.i2c_bus_idle === 1'b0)) begin
        @(posedge clk);
        cycles++;
        if (cycles > TIMEOUT_CYCLES) begin
          $fatal(1, "Timeout waiting for cmd_ready in HOLD");
        end
      end
    end
  endtask

  task automatic wait_bus_idle;
    int cycles;
    begin
      cycles = 0;
      while (!(dut.i2c_cmd_ready === 1'b1 && dut.i2c_bus_idle === 1'b1)) begin
        @(posedge clk);
        cycles++;
        if (cycles > TIMEOUT_CYCLES) begin
          $fatal(1, "Timeout waiting for bus idle");
        end
      end
    end
  endtask

  task automatic wait_scl_posedge(input string what);
    bit edge_seen;
    begin
      edge_seen = 1'b0;
      fork
        begin
          @(posedge scl_line);
          edge_seen = 1'b1;
        end
        begin
          repeat (TIMEOUT_CYCLES) @(posedge clk);
          if (!edge_seen) begin
            $fatal(1, "Timeout waiting for posedge scl_line during %s", what);
          end
        end
      join_any
      disable fork;
    end
  endtask

  task automatic wait_scl_negedge(input string what);
    bit edge_seen;
    begin
      edge_seen = 1'b0;
      fork
        begin
          @(negedge scl_line);
          edge_seen = 1'b1;
        end
        begin
          repeat (TIMEOUT_CYCLES) @(posedge clk);
          if (!edge_seen) begin
            $fatal(1, "Timeout waiting for negedge scl_line during %s", what);
          end
        end
      join_any
      disable fork;
    end
  endtask

  task automatic wait_scl_low(input string what);
    int cycles;
    begin
      cycles = 0;
      while (scl_line !== 1'b0) begin
        @(posedge clk);
        cycles++;
        if (cycles > TIMEOUT_CYCLES) begin
          $fatal(1, "Timeout waiting for scl_line low during %s", what);
        end
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Reset
  // --------------------------------------------------------------------------
  task automatic reset_dut;
    begin
      rst_n               = 1'b0;
      req_valid           = 1'b0;
      req_write           = 1'b0;
      req_addr            = '0;
      req_wdata           = '0;
      req_wstrb           = '0;
      rsp_ready           = 1'b0;
      slave_sda_drive_low = 1'b0;

      repeat (5) @(posedge clk);
      rst_n = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  // --------------------------------------------------------------------------
  // MMIO helpers
  // --------------------------------------------------------------------------
  task automatic mmio_write(
    input logic [ADDR_W-1:0]       addr,
    input logic [DATA_W-1:0]       data,
    input logic [(DATA_W/8)-1:0]   strb,
    input logic                    exp_err
  );
    begin
      @(negedge clk);
      req_valid <= 1'b1;
      req_write <= 1'b1;
      req_addr  <= addr;
      req_wdata <= data;
      req_wstrb <= strb;

      wait_req_ready(addr);

      @(negedge clk);
      req_valid <= 1'b0;
      req_write <= 1'b0;
      req_addr  <= '0;
      req_wdata <= '0;
      req_wstrb <= '0;

      wait_rsp_valid(addr);
      if (rsp_err !== exp_err) begin
        $fatal(1, "MMIO write addr 0x%0h expected rsp_err=%0b got %0b", addr, exp_err, rsp_err);
      end

      @(negedge clk);
      rsp_ready <= 1'b1;
      @(posedge clk);
      @(negedge clk);
      rsp_ready <= 1'b0;
    end
  endtask

  task automatic mmio_read(
    input  logic [ADDR_W-1:0]     addr,
    output logic [DATA_W-1:0]     data,
    input  logic                  exp_err
  );
    begin
      @(negedge clk);
      req_valid <= 1'b1;
      req_write <= 1'b0;
      req_addr  <= addr;
      req_wdata <= '0;
      req_wstrb <= '0;

      wait_req_ready(addr);

      @(negedge clk);
      req_valid <= 1'b0;
      req_addr  <= '0;

      wait_rsp_valid(addr);
      if (rsp_err !== exp_err) begin
        $fatal(1, "MMIO read addr 0x%0h expected rsp_err=%0b got %0b", addr, exp_err, rsp_err);
      end
      data = rsp_rdata;

      @(negedge clk);
      rsp_ready <= 1'b1;
      @(posedge clk);
      @(negedge clk);
      rsp_ready <= 1'b0;
    end
  endtask

  // --------------------------------------------------------------------------
  // Small I2C slave BFMs
  // --------------------------------------------------------------------------
  task automatic slave_expect_write_byte(
    input logic [7:0] exp_byte,
    input logic       ack_low
  );
    logic [7:0] got_byte;
    int i;
    begin
      got_byte = '0;
      slave_sda_drive_low <= 1'b0;

      for (i = 7; i >= 0; i = i - 1) begin
        wait_scl_posedge($sformatf("write byte bit %0d sample", i));
        got_byte[i] = sda_line;
        wait_scl_negedge($sformatf("write byte bit %0d complete", i));
      end

      if (got_byte !== exp_byte) begin
        $fatal(1, "Slave saw write byte 0x%02h, expected 0x%02h", got_byte, exp_byte);
      end

      slave_sda_drive_low <= ack_low;
      wait_scl_posedge("slave ACK/NACK bit");
      wait_scl_negedge("slave ACK/NACK release");
      slave_sda_drive_low <= 1'b0;
    end
  endtask

  task automatic slave_send_read_byte(
    input  logic [7:0] send_byte,
    output logic       master_ack_low
  );
    int i;
    begin
      slave_sda_drive_low <= 1'b0;
      master_ack_low      = 1'b0;

      // Important: align to the current low phase.
      // RD_CMD begins while SCL is already low, so waiting for a *new*
      // negedge would start one half-cycle late.
      wait_scl_low("read byte start");

      for (i = 7; i >= 0; i = i - 1) begin
        slave_sda_drive_low <= ~send_byte[i]; // 0 => drive low, 1 => release
        wait_scl_posedge($sformatf("read byte bit %0d sample", i));
        wait_scl_negedge($sformatf("read byte bit %0d complete", i));
      end

      // Release SDA for master's ACK/NACK bit
      slave_sda_drive_low <= 1'b0;
      wait_scl_posedge("master ACK/NACK sample");
      master_ack_low = (sda_line === 1'b0);
      wait_scl_negedge("master ACK/NACK complete");
    end
  endtask

  // --------------------------------------------------------------------------
  // Test sequence
  // --------------------------------------------------------------------------
  initial begin
    reset_dut();

    // Reset sanity
    mmio_read(REG_STATUS, rd_data, 1'b0);
    if (rd_data[STATUS_CMD_READY] !== 1'b1 || rd_data[STATUS_BUS_IDLE] !== 1'b1) begin
      $fatal(1, "Reset STATUS expected cmd_ready=1 and bus_idle=1, got 0x%08h", rd_data);
    end

    mmio_read(REG_DIVISOR, rd_data, 1'b0);
    if (rd_data[DIVISOR_W-1:0] !== 16'd2) begin
      $fatal(1, "Reset divisor expected MIN_DIVISOR=2, got 0x%08h", rd_data);
    end

    // Basic RW storage checks
    mmio_write(REG_DIVISOR, 32'd3, 4'hF, 1'b0);
    mmio_read(REG_DIVISOR, rd_data, 1'b0);
    if (rd_data[DIVISOR_W-1:0] !== 16'd3) begin
      $fatal(1, "REG_DIVISOR readback mismatch: 0x%08h", rd_data);
    end

    mmio_write(REG_TXDATA, 32'h000000A0, 4'h1, 1'b0);
    mmio_read(REG_TXDATA, rd_data, 1'b0);
    if (rd_data[7:0] !== 8'hA0) begin
      $fatal(1, "REG_TXDATA readback mismatch: 0x%08h", rd_data);
    end

    // REG_CMD byte-0 absent must error and must not launch
    mmio_write(REG_CMD, 32'h00000100, 4'b0010, 1'b1);
    if (dut.i2c_bus_idle !== 1'b1) begin
      $fatal(1, "Partial REG_CMD write should not have launched a command");
    end

    // START command
    mmio_write(REG_CMD, {{(DATA_W-CMD_W){1'b0}}, START_CMD}, 4'h1, 1'b0);

    // Command while not ready should error
    mmio_write(REG_CMD, {{(DATA_W-CMD_W){1'b0}}, WR_CMD}, 4'h1, 1'b1);

    wait_cmd_ready_in_hold();

    // WR command with slave ACK
    mmio_write(REG_TXDATA, 32'h000000A0, 4'h1, 1'b0);
    fork
      begin
        slave_expect_write_byte(8'hA0, 1'b1); // ACK => drive SDA low
      end
      begin
        mmio_write(REG_CMD, {{(DATA_W-CMD_W){1'b0}}, WR_CMD}, 4'h1, 1'b0);
      end
    join

    wait_cmd_ready_in_hold();
    if (dut.i2c_ack !== 1'b0) begin
      $fatal(1, "Expected slave ACK=0 after WR byte");
    end

    // RD command with ACK from master (rd_last = 0)
    fork
      begin
        slave_send_read_byte(8'h5A, master_ack_low);
      end
      begin
        mmio_write(REG_CMD, {{(DATA_W-CMD_W){1'b0}}, RD_CMD}, 4'h1, 1'b0);
      end
    join

    wait_cmd_ready_in_hold();
    mmio_read(REG_RXDATA, rd_data, 1'b0);
    if (rd_data[7:0] !== 8'h5A) begin
      $fatal(1, "Expected RXDATA=0x5A, got 0x%08h", rd_data);
    end
    if (master_ack_low !== 1'b1) begin
      $fatal(1, "Expected master to ACK first read byte");
    end

    // RD command with NACK from master (rd_last = 1)
    fork
      begin
        slave_send_read_byte(8'hA5, master_ack_low_last);
      end
      begin
        mmio_write(REG_CMD, 32'h00000102, 4'h3, 1'b0); // bit8=1, cmd=RD_CMD
      end
    join

    wait_cmd_ready_in_hold();
    mmio_read(REG_RXDATA, rd_data, 1'b0);
    if (rd_data[7:0] !== 8'hA5) begin
      $fatal(1, "Expected RXDATA=0xA5, got 0x%08h", rd_data);
    end
    if (master_ack_low_last !== 1'b0) begin
      $fatal(1, "Expected master to NACK last read byte");
    end

    // STOP command
    mmio_write(REG_CMD, {{(DATA_W-CMD_W){1'b0}}, STOP_CMD}, 4'h1, 1'b0);
    wait_bus_idle();

    mmio_read(REG_STATUS, rd_data, 1'b0);
    if (rd_data[STATUS_BUS_IDLE] !== 1'b1) begin
      $fatal(1, "Expected bus_idle after STOP, got STATUS=0x%08h", rd_data);
    end

    $display("tb_i2c_regs: PASS");
    #50;
    $finish;
  end

endmodule