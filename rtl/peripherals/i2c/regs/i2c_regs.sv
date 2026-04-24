// i2c_regs.sv
//------------------------------------------------------------------------------
// I2C register block V2
//
// Goal of this version: V2
// - Keep "state" bits live:
//     * cmd_ready
//     * bus_idle
//     * master_receiving
// - Make "event/result" bits sticky so software does not have to poll every cycle:
//     * done
//     * ack_valid
//     * ack
//     * rd_data_valid
//     * cmd_illegal
//
// Sticky bits are cleared in two ways:
// 1) W1C via REG_STATUS write
// 2) Automatically when a new command is successfully launched
//
// This allows software to:
// - Check cmd_ready before issuing a command
// - Launch the command and return immediately
// - Later poll sticky completion/result bits when convenient
//------------------------------------------------------------------------------
// Register map
//
// 0x00 REG_STATUS   (R / W1C for sticky bits)
//      [0] cmd_ready         (live, read-only behavior)
//      [1] bus_idle          (live, read-only behavior)
//      [2] done              (sticky, W1C)
//      [3] ack_valid         (sticky, W1C)
//      [4] ack               (latched with ack_valid, W1C with ack_valid)
//      [5] rd_data_valid     (sticky, W1C)
//      [6] cmd_illegal       (sticky, W1C)
//      [7] master_receiving  (live, read-only behavior)
//
// 0x04 REG_DIVISOR  (R/W)
//      [DIVISOR_W-1:0] divisor
//
// 0x08 REG_TXDATA   (R/W)
//      [7:0] tx byte staging register
//
// 0x0C REG_RXDATA   (R)
//      [7:0] last captured RX byte
//
// 0x10 REG_CMD      (W)
//      [2:0] cmd
//      [8]   rd_last
//
// REG_CMD encodings:
//   3'h0 : START_CMD
//   3'h1 : WR_CMD
//   3'h2 : RD_CMD
//   3'h3 : STOP_CMD
//   3'h4 : RESTART_CMD
//   3'h5 : illegal
//   3'h6 : illegal
//   3'h7 : illegal
//
// rd_last usage:
//   Used with RD_CMD only:
//   0 = after reading a byte, master sends ACK  (more bytes coming)
//   1 = after reading a byte, master sends NACK (last byte)
//------------------------------------------------------------------------------
module i2c_regs #(
    parameter int                     ADDR_W       = 12,
    parameter int                     DATA_W       = 32,
    parameter int                     BYTE_W       = 8,
    parameter int                     CMD_W        = 3,
    parameter int                     DIVISOR_W    = 16,
    parameter logic [DIVISOR_W-1:0]   MIN_DIVISOR  = 'd1
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Generic project MMIO request channel
    input  logic                    req_valid,
    output logic                    req_ready,
    input  logic                    req_write,
    input  logic [ADDR_W-1:0]       req_addr,
    input  logic [DATA_W-1:0]       req_wdata,
    input  logic [(DATA_W/8)-1:0]   req_wstrb,

    // Generic project MMIO response channel
    output logic                    rsp_valid,
    input  logic                    rsp_ready,
    output logic [DATA_W-1:0]       rsp_rdata,
    output logic                    rsp_err,

    // External I2C pins / pin-control
    input  logic                    sda_in,
    output logic                    sda_out,
    input  logic                    scl_in,
    output logic                    scl_out,
    output logic                    master_receiving_o
);

    //--------------------------------------------------------------------------
    // Local register addresses
    //--------------------------------------------------------------------------
    localparam logic [ADDR_W-1:0] REG_STATUS   = 12'h000;
    localparam logic [ADDR_W-1:0] REG_DIVISOR  = 12'h004;
    localparam logic [ADDR_W-1:0] REG_TXDATA   = 12'h008;
    localparam logic [ADDR_W-1:0] REG_RXDATA   = 12'h00C;
    localparam logic [ADDR_W-1:0] REG_CMD      = 12'h010;
	 localparam logic	[ADDR_W-1:0] REG_DEBUG	  = 12'h014;

    //--------------------------------------------------------------------------
    // Status bit positions
    //--------------------------------------------------------------------------
    localparam int unsigned STATUS_CMD_READY        = 0;
    localparam int unsigned STATUS_BUS_IDLE         = 1;
    localparam int unsigned STATUS_DONE             = 2;
    localparam int unsigned STATUS_ACK_VALID        = 3;
    localparam int unsigned STATUS_ACK              = 4;
    localparam int unsigned STATUS_RD_DATA_VALID    = 5;
    localparam int unsigned STATUS_CMD_ILLEGAL      = 6;
    localparam int unsigned STATUS_MASTER_RECEIVING = 7;

    //--------------------------------------------------------------------------
    // I2C core interface signals
    //--------------------------------------------------------------------------
    logic [BYTE_W-1:0] i2c_rx_data;
    logic              i2c_cmd_ready;
    logic              i2c_cmd_illegal;
    logic              i2c_done_tick;
    logic              i2c_ack;
    logic              i2c_ack_valid;
    logic              i2c_rd_data_valid;
    logic              i2c_bus_idle;
    logic              i2c_master_receiving;

    //--------------------------------------------------------------------------
    // Software-visible storage registers
    //--------------------------------------------------------------------------
    logic [BYTE_W-1:0]  txdata_reg;
    logic [BYTE_W-1:0]  rxdata_reg;
    logic [DIVISOR_W-1:0] divisor_reg;

    // Sticky status registers
    logic done_sticky;
    logic ack_valid_sticky;
    logic ack_sticky;
    logic rd_data_valid_sticky;
    logic cmd_illegal_sticky;

    //--------------------------------------------------------------------------
    // Generic MMIO handshake
    //--------------------------------------------------------------------------
    logic req_fire;
    logic wr_fire;
    logic rsp_fire;

    assign rsp_fire  = rsp_valid && rsp_ready;
    assign req_ready = (!rsp_valid) || rsp_fire;
    assign req_fire  = req_valid && req_ready;
    assign wr_fire   = req_fire && req_write;

    //--------------------------------------------------------------------------
    // Write decode helpers
    //--------------------------------------------------------------------------
    logic wr_status_fire;
    logic wr_divisor_fire;
    logic wr_txdata_fire;
    logic wr_cmd_fire;

    assign wr_status_fire  = wr_fire && (req_addr == REG_STATUS);
    assign wr_divisor_fire = wr_fire && (req_addr == REG_DIVISOR);
    assign wr_txdata_fire  = wr_fire && (req_addr == REG_TXDATA);
    assign wr_cmd_fire     = wr_fire && (req_addr == REG_CMD);

    //--------------------------------------------------------------------------
    // Helper function: byte-write merge for a generic DATA_W register
    //--------------------------------------------------------------------------
    function    automatic   logic   [DATA_W-1:0]    merge_wstrb(
    input   logic   [DATA_W-1:0]        old_val,
    input   logic   [DATA_W-1:0]        new_val,
    input   logic   [(DATA_W/8)-1:0]    strb);

    logic   [DATA_W-1:0]    write_mask;
    begin
        write_mask  =   {
            {8{strb[3]}},
            {8{strb[2]}},
            {8{strb[1]}},
            {8{strb[0]}}
        };
        
        return  (old_val    &   ~write_mask)    |   (new_val & write_mask);
    end
    endfunction

    //--------------------------------------------------------------------------
    // Temporary merged values and command launch payload
    //--------------------------------------------------------------------------
    logic [DATA_W-1:0] status_w1c_merged;
    logic [DATA_W-1:0] divisor_merged;
    logic [DATA_W-1:0] txdata_merged;
    logic [DATA_W-1:0] cmd_merged;

    logic [CMD_W-1:0]  launch_cmd;
    logic              launch_rd_last;
    logic              launch_cmd_fire;

    assign status_w1c_merged = merge_wstrb('0, req_wdata, req_wstrb);
    assign divisor_merged    = merge_wstrb({{(DATA_W-DIVISOR_W){1'b0}}, divisor_reg}, req_wdata, req_wstrb);
    assign txdata_merged     = merge_wstrb({{(DATA_W-BYTE_W){1'b0}},    txdata_reg},  req_wdata, req_wstrb);
    assign cmd_merged        = merge_wstrb('0, req_wdata, req_wstrb);

    // REG_CMD is action-oriented, not retained state.
    // A command launch only happens when:
    // - software writes REG_CMD
    // - byte lane 0 is enabled
    // - the I2C core reports cmd_ready
    assign launch_cmd_fire = wr_cmd_fire && req_wstrb[0] && i2c_cmd_ready;
    assign launch_cmd      = cmd_merged[CMD_W-1:0];
    assign launch_rd_last  = cmd_merged[8];

    //--------------------------------------------------------------------------
    // Status register assembly
    //--------------------------------------------------------------------------
    logic [DATA_W-1:0] status_rdata;

    always_comb begin
        status_rdata = '0;

        // Live status bits
        status_rdata[STATUS_CMD_READY]        = i2c_cmd_ready;
        status_rdata[STATUS_BUS_IDLE]         = i2c_bus_idle;
        status_rdata[STATUS_MASTER_RECEIVING] = i2c_master_receiving;

        // Sticky / latched bits
        status_rdata[STATUS_DONE]          = done_sticky;
        status_rdata[STATUS_ACK_VALID]     = ack_valid_sticky;
        status_rdata[STATUS_ACK]           = ack_sticky;
        status_rdata[STATUS_RD_DATA_VALID] = rd_data_valid_sticky;
        status_rdata[STATUS_CMD_ILLEGAL]   = cmd_illegal_sticky;
    end

    //--------------------------------------------------------------------------
    // Read mux / response decode
    //
    // REG_STATUS write semantics:
    // - allowed
    // - W1C only affects sticky bits
    // - live bits ignore writes
    //--------------------------------------------------------------------------
    logic [DATA_W-1:0] rdata_next;
    logic              err_next;

    always_comb begin
        rdata_next = '0;
        err_next   = 1'b0;

        unique case (req_addr)
            REG_STATUS: begin
                if (!req_write)
					 begin
                    rdata_next = status_rdata;
                end
                // writes are allowed for W1C clearing of sticky bits
            end
				
				REG_DEBUG: begin
                if (req_write)
					 begin
						err_next	=	1'b1;
					end
					else
					begin
						rdata_next = 32'hDECAFBAD;
					end
            end

            REG_DIVISOR: begin
                rdata_next =	32'hD06A0000	| {{(DATA_W-DIVISOR_W){1'b0}}, divisor_reg};
            end

            REG_TXDATA: begin
                rdata_next = {{(DATA_W-BYTE_W){1'b0}}, txdata_reg};
            end

            REG_RXDATA: begin
                if (req_write) begin
                    err_next = 1'b1;
                end else begin
                    rdata_next = {{(DATA_W-BYTE_W){1'b0}}, rxdata_reg};
                end
            end

            REG_CMD: begin
                if (!req_write) begin
                    err_next = 1'b1;
                end else if (!req_wstrb[0]) begin
                    err_next = 1'b1;
                end else if (!i2c_cmd_ready) begin
                    err_next = 1'b1;
                end
            end

            default: begin
                err_next = 1'b1;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // Stored register updates
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txdata_reg   <= '0;
            rxdata_reg   <= '0;
            divisor_reg  <= MIN_DIVISOR;
        end else begin
            // Hold the most recent received byte for software
            if (i2c_rd_data_valid) begin
                rxdata_reg <= i2c_rx_data;
            end

            if (wr_txdata_fire) begin
                txdata_reg <= txdata_merged[BYTE_W-1:0];
            end

            if (wr_divisor_fire) begin
                divisor_reg <= divisor_merged[DIVISOR_W-1:0];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sticky status management
    //
    // Clear precedence:
    // 1) W1C writes can clear sticky bits
    // 2) launching a new command clears old completion/result bits
    // 3) new hardware events set sticky bits
    //
    // Because these are nonblocking assignments, the later "set" logic wins if
    // a clear and a new event happen in the same cycle.
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done_sticky          <= 1'b0;
            ack_valid_sticky     <= 1'b0;
            ack_sticky           <= 1'b0;
            rd_data_valid_sticky <= 1'b0;
            cmd_illegal_sticky   <= 1'b0;
        end else begin
            // W1C clears from REG_STATUS write
            if (wr_status_fire) begin
                if (status_w1c_merged[STATUS_DONE]) begin
                    done_sticky <= 1'b0;
                end

                // Clear ACK result as a pair so software never sees ACK without
                // a matching valid bit.
                if (status_w1c_merged[STATUS_ACK_VALID] ||
                    status_w1c_merged[STATUS_ACK]) begin
                    ack_valid_sticky <= 1'b0;
                    ack_sticky       <= 1'b0;
                end

                if (status_w1c_merged[STATUS_RD_DATA_VALID]) begin
                    rd_data_valid_sticky <= 1'b0;
                end

                if (status_w1c_merged[STATUS_CMD_ILLEGAL]) begin
                    cmd_illegal_sticky <= 1'b0;
                end
            end

            // Automatically clear old results when a new command is accepted
            if (launch_cmd_fire) begin
                done_sticky          <= 1'b0;
                ack_valid_sticky     <= 1'b0;
                ack_sticky           <= 1'b0;
                rd_data_valid_sticky <= 1'b0;
                cmd_illegal_sticky   <= 1'b0;
            end

            // Latch new events/results from the I2C core
            if (i2c_done_tick) begin
                done_sticky <= 1'b1;
            end

            if (i2c_ack_valid) begin
                ack_valid_sticky <= 1'b1;
                ack_sticky       <= i2c_ack;
            end

            if (i2c_rd_data_valid) begin
                rd_data_valid_sticky <= 1'b1;
            end

            if (i2c_cmd_illegal) begin
                cmd_illegal_sticky <= 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Response channel
    //
    // One response per accepted request.
    // Response is held until rsp_ready.
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rsp_valid <= 1'b0;
            rsp_rdata <= '0;
            rsp_err   <= 1'b0;
        end else begin
            if (rsp_fire) begin
                rsp_valid <= 1'b0;
            end

            if (req_fire) begin
                rsp_valid <= 1'b1;
                rsp_rdata <= rdata_next;
                rsp_err   <= err_next;
            end
        end
    end

    //--------------------------------------------------------------------------
    // I2C core instance
    //--------------------------------------------------------------------------
    i2c_master #(
        .DIVISOR_W   (DIVISOR_W),
        .BYTE_W      (BYTE_W),
        .CMD_W       (CMD_W),
        .MIN_DIVISOR (MIN_DIVISOR)
    ) u_i2c_master (
        .clk                (clk),
        .rst_n              (rst_n),
        .divisor            (divisor_reg),

        .rx_data_o          (i2c_rx_data),
        .tx_data_i          (txdata_reg),
        .rd_last_i          (launch_rd_last),

        .sda_in             (sda_in),
        .sda_out            (sda_out),
        .scl_in             (scl_in),
        .scl_out            (scl_out),

        .cmd                (launch_cmd),
        .cmd_illegal_o      (i2c_cmd_illegal),
        .cmd_valid_i        (launch_cmd_fire),
        .cmd_ready_o        (i2c_cmd_ready),

        .done_tick_o        (i2c_done_tick),
        .ack_o              (i2c_ack),
        .ack_valid_o        (i2c_ack_valid),
        .rd_data_valid_o    (i2c_rd_data_valid),
        .bus_idle_o         (i2c_bus_idle),
        .master_receiving_o (i2c_master_receiving)
    );

    assign master_receiving_o = i2c_master_receiving;

endmodule