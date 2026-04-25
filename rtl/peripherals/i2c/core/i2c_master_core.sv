// i2c_master_core.sv
//
// V1.6 improvements over V1.5:
// - synchronize scl_in and sda_in into the local clk domain
// - qualify SCL-high with a small digital filter
// - filter SDA before sampling
// - sample SDA later in the confirmed SCL-high window
// - detect SDA instability while SCL is high during data phases
// - auto-abort on detected protocol fault
// - export sticky hardware fault signals for software-visible debug
//
// Notes:
// - still not full clock-stretch support
// - still single-master oriented
// - same general FSM structure as V1.5
//
module i2c_master
#(
    parameter int unsigned DIVISOR_W = 16,
    parameter int unsigned BYTE_W    = 8,
    parameter int unsigned CMD_W     = 3,
    parameter logic [DIVISOR_W-1:0] MIN_DIVISOR = 'd1,

    // Maximum number of local clk cycles to wait for SCL to actually rise
    // in a released-high phase before flagging a timeout fault.
    parameter int unsigned HIGH_WAIT_TIMEOUT_W = 16,
    parameter logic [HIGH_WAIT_TIMEOUT_W-1:0] HIGH_WAIT_TIMEOUT_CLKS = 16'd4095
)
(
    input  logic                 clk,
    input  logic                 rst_n,

    // I2C timing divisor.
    // One I2C bit is broken into 4 phases.
    input  logic [DIVISOR_W-1:0] divisor,

    // RX/TX data path.
    output logic [BYTE_W-1:0]    rx_data_o,
    input  logic [BYTE_W-1:0]    tx_data_i,
    input  logic                 rd_last_i,

    // Raw I2C bus pins.
    // The top-level is expected to implement open-drain behavior.
    input  logic                 sda_in,
    output logic                 sda_out,

    input  logic                 scl_in,
    output logic                 scl_out,

    // Command interface.
    // Legal commands:
    // - START in IDLE
    // - WR/RD/STOP/RESTART in HOLD
    input  logic [CMD_W-1:0]     cmd,
    output logic                 cmd_illegal_o,
    input  logic                 cmd_valid_i,
    output logic                 cmd_ready_o,

    // External best-effort abort request.
    input  logic                 abort_i,

    // Command result strobes.
    output logic                 done_tick_o,
    output logic                 ack_o,
    output logic                 ack_valid_o,
    output logic                 rd_data_valid_o,

    // Status outputs.
    output logic                 bus_idle_o,
    output logic                 master_receiving_o,

    // Sticky hardware fault outputs for debug.
    output logic                 fault_any_o,
    output logic                 fault_abort_seen_o,
    output logic                 fault_sda_unstable_o,
    output logic                 fault_scl_high_timeout_o
);

    //--------------------------------------------------------------------------
    // Command encodings
    //--------------------------------------------------------------------------
    localparam logic [CMD_W-1:0] START_CMD   = 'h0;
    localparam logic [CMD_W-1:0] WR_CMD      = 'h1;
    localparam logic [CMD_W-1:0] RD_CMD      = 'h2;
    localparam logic [CMD_W-1:0] STOP_CMD    = 'h3;
    localparam logic [CMD_W-1:0] RESTART_CMD = 'h4;

    //--------------------------------------------------------------------------
    // FSM states
    //
    // START / STOP / RESTART use half-bit timing.
    // DATA states use the 4 quarter-phases of one I2C bit cell.
    //--------------------------------------------------------------------------
    typedef enum logic [3:0]
    {
        S_IDLE      = 4'h0,
        S_START_1   = 4'h1,
        S_START_2   = 4'h2,
        S_HOLD      = 4'h3,
        S_RESTART   = 4'h4,
        S_STOP_1    = 4'h5,
        S_STOP_2    = 4'h6,
        S_DATA_1    = 4'h7,
        S_DATA_2    = 4'h8,
        S_DATA_3    = 4'h9,
        S_DATA_4    = 4'hA,
        S_DATA_END  = 4'hB,
        S_ABORT_1   = 4'hC,
        S_ABORT_2   = 4'hD
    } state_t;

    //--------------------------------------------------------------------------
    // Helper: 3-input majority vote
    //
    // Used as a tiny digital filter for sampled inputs.
    //--------------------------------------------------------------------------
    function automatic logic majority3
    (
        input logic a,
        input logic b,
        input logic c
    );
    begin
        majority3 = (a & b) | (a & c) | (b & c);
    end
    endfunction

    //--------------------------------------------------------------------------
    // State / datapath registers
    //--------------------------------------------------------------------------
    state_t state_reg, state_next;

    // Counts local clk cycles inside the current phase.
    logic [DIVISOR_W-1:0] tick_cnt_reg, tick_cnt_next;

    // Latched divisor used for one whole transaction.
    // The divisor only updates when a START begins from IDLE.
    logic [DIVISOR_W-1:0] divisor_reg, divisor_next;
    logic [DIVISOR_W-1:0] divisor_clamped;

    // quarter_cnt = one quarter-phase
    // half_cnt_wide = two quarter-phases
    logic [DIVISOR_W-1:0] quarter_cnt;
    logic [DIVISOR_W:0]   half_cnt_wide;

    // 9-bit transmit / receive shift registers.
    // For write:
    //   8 data bits + 1 ACK slot
    // For read:
    //   8 received bits + final ACK/NACK bit from master
    logic [BYTE_W:0]      tx_reg, tx_next;
    logic [BYTE_W:0]      rx_reg, rx_next;

    // Active command latched at command acceptance.
    logic [CMD_W-1:0]     cmd_reg, cmd_next;

    // Bit index:
    // 0..7 = data bits
    // 8    = ACK/NACK phase
    logic [$clog2(BYTE_W+1)-1:0] bit_idx_reg, bit_idx_next;

    // Open-drain output controls:
    // 1 = release line
    // 0 = drive low
    logic                 sda_out_reg, sda_out_next;
    logic                 scl_out_reg, scl_out_next;

    // Internal helpers / status.
    logic                 done_tick_int;
    logic                 receiving_f;
    logic                 data_phase;

    // True only when it is time to sample SDA into the RX shift register.
    logic                 sample_sda_now;

    // True when the core is allowed to move through a released-high phase.
    logic                 high_phase_ready;

    // True when abort/recovery should take priority.
    logic                 abort_fire;

    //--------------------------------------------------------------------------
    // Input synchronizers / filters
    //
    // Because scl_in and sda_in are asynchronous to clk, first synchronize them,
    // then build a short history for filtering / qualification.
    //--------------------------------------------------------------------------
    logic scl_meta_reg;
    logic scl_sync_reg;
    logic sda_meta_reg;
    logic sda_sync_reg;

    logic [2:0] scl_hist_reg;
    logic [2:0] sda_hist_reg;

    // Qualified "SCL is really high" signal.
    logic       scl_high_qual;

    // Filtered SDA level.
    logic       sda_filt;
    logic       sda_filt_prev_reg;

    //--------------------------------------------------------------------------
    // High-phase wait watchdog
    //
    // Used to detect cases where SCL was released but never actually rose high.
    //--------------------------------------------------------------------------
    logic [HIGH_WAIT_TIMEOUT_W-1:0] high_wait_cnt_reg, high_wait_cnt_next;
    logic                           waiting_for_high_phase;
    logic                           scl_high_timeout_event;

    //--------------------------------------------------------------------------
    // Protocol-fault detection
    //
    // During a stable data-high phase, SDA should not move.
    //--------------------------------------------------------------------------
    logic protocol_fault_event;

    //--------------------------------------------------------------------------
    // Sticky fault registers
    //
    // These are latched internally and then exported as outputs.
    //--------------------------------------------------------------------------
    logic fault_abort_seen_reg;
    logic fault_sda_unstable_reg;
    logic fault_scl_high_timeout_reg;

    //--------------------------------------------------------------------------
    // Legal event / command detection
    //
    // Accepted commands:
    // - START only in S_IDLE
    // - WR/RD/STOP/RESTART only in S_HOLD
    //--------------------------------------------------------------------------
    logic idle_start_fire;
    logic hold_wr_fire;
    logic hold_rd_fire;
    logic hold_stop_fire;
    logic hold_restart_fire;
    logic hold_cmd_fire;
    logic cmd_fire;

    assign idle_start_fire   = (state_reg == S_IDLE) && cmd_valid_i && (cmd == START_CMD);
    assign hold_wr_fire      = (state_reg == S_HOLD) && cmd_valid_i && (cmd == WR_CMD);
    assign hold_rd_fire      = (state_reg == S_HOLD) && cmd_valid_i && (cmd == RD_CMD);
    assign hold_stop_fire    = (state_reg == S_HOLD) && cmd_valid_i && (cmd == STOP_CMD);
    assign hold_restart_fire = (state_reg == S_HOLD) && cmd_valid_i && (cmd == RESTART_CMD);

    assign hold_cmd_fire = hold_wr_fire || hold_rd_fire || hold_stop_fire || hold_restart_fire;
    assign cmd_fire      = idle_start_fire || hold_cmd_fire;

    // Abort can come from:
    // - external abort_i
    // - detected SDA protocol fault
    // - detected SCL-high timeout fault
    assign abort_fire = (abort_i || protocol_fault_event || scl_high_timeout_event) &&
                        (state_reg != S_IDLE);

    //--------------------------------------------------------------------------
    // Illegal command pulse
    //
    // Combinational pulse whenever cmd_valid_i is asserted with an unsupported
    // command for the current state.
    //--------------------------------------------------------------------------
    always_comb
    begin
        cmd_illegal_o = 1'b0;

        if ((state_reg == S_IDLE) && cmd_valid_i && (cmd != START_CMD))
        begin
            cmd_illegal_o = 1'b1;
        end

        if ((state_reg == S_HOLD) && cmd_valid_i &&
            (cmd != WR_CMD) && (cmd != RD_CMD) &&
            (cmd != STOP_CMD) && (cmd != RESTART_CMD))
        begin
            cmd_illegal_o = 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // Clamp divisor
    //
    // Prevent illegal or too-small timing.
    //--------------------------------------------------------------------------
    always_comb
    begin
        if (divisor < MIN_DIVISOR)
        begin
            divisor_clamped = MIN_DIVISOR;
        end
        else
        begin
            divisor_clamped = divisor;
        end
    end

    assign quarter_cnt   = divisor_reg;
    assign half_cnt_wide = {1'b0, divisor_reg} << 1;

    //--------------------------------------------------------------------------
    // Qualified SCL-high and filtered SDA
    //
    // scl_high_qual:
    //   requires the last three synchronized SCL samples to be high
    //
    // sda_filt:
    //   majority-vote of the last three synchronized SDA samples
    //--------------------------------------------------------------------------
    assign scl_high_qual = &scl_hist_reg;
    assign sda_filt      = majority3(sda_hist_reg[2], sda_hist_reg[1], sda_hist_reg[0]);

    //--------------------------------------------------------------------------
    // High-phase qualifier
    //
    // In released-high phases, do not assume SCL is high immediately.
    // Wait for the qualified-high indication instead.
    //--------------------------------------------------------------------------
    always_comb
    begin
        high_phase_ready = 1'b1;

        case (state_reg)
            S_START_1,
            S_RESTART,
            S_STOP_1,
            S_STOP_2,
            S_DATA_2,
            S_DATA_3:
            begin
                high_phase_ready = scl_high_qual;
            end

            default:
            begin
                high_phase_ready = 1'b1;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // Waiting-for-high detection
    //
    // True when the FSM is in a released-high phase but the bus has not yet
    // reached qualified-high.
    //--------------------------------------------------------------------------
    always_comb
    begin
        waiting_for_high_phase = 1'b0;

        case (state_reg)
            S_START_1,
            S_RESTART,
            S_STOP_1,
            S_STOP_2,
            S_DATA_2,
            S_DATA_3:
            begin
                if (!high_phase_ready)
                begin
                    waiting_for_high_phase = 1'b1;
                end
            end

            default:
            begin
                waiting_for_high_phase = 1'b0;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // SCL-high timeout event
    //
    // If the core released SCL but it never reached qualified-high within the
    // watchdog window, raise a hardware timeout event.
    //--------------------------------------------------------------------------
    always_comb
    begin
        scl_high_timeout_event = 1'b0;

        if (waiting_for_high_phase &&
            (high_wait_cnt_reg == HIGH_WAIT_TIMEOUT_CLKS))
        begin
            scl_high_timeout_event = 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // Protocol fault event
    //
    // During S_DATA_3, SCL is supposed to be stably high and SDA should be
    // stable. If filtered SDA changes during that window, flag a fault.
    //--------------------------------------------------------------------------
    always_comb
    begin
        protocol_fault_event = 1'b0;

        if ((state_reg == S_DATA_3) && scl_high_qual)
        begin
            if (sda_filt != sda_filt_prev_reg)
            begin
                protocol_fault_event = 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sequential registers
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            state_reg                  <= S_IDLE;
            tick_cnt_reg               <= '0;
            bit_idx_reg                <= '0;
            cmd_reg                    <= START_CMD;
            tx_reg                     <= '0;
            rx_reg                     <= '0;
            divisor_reg                <= MIN_DIVISOR;
            sda_out_reg                <= 1'b1;
            scl_out_reg                <= 1'b1;

            scl_meta_reg               <= 1'b1;
            scl_sync_reg               <= 1'b1;
            sda_meta_reg               <= 1'b1;
            sda_sync_reg               <= 1'b1;
            scl_hist_reg               <= 3'b111;
            sda_hist_reg               <= 3'b111;
            sda_filt_prev_reg          <= 1'b1;

            high_wait_cnt_reg          <= '0;

            fault_abort_seen_reg       <= 1'b0;
            fault_sda_unstable_reg     <= 1'b0;
            fault_scl_high_timeout_reg <= 1'b0;
        end
        else
        begin
            state_reg    <= state_next;
            tick_cnt_reg <= tick_cnt_next;
            bit_idx_reg  <= bit_idx_next;
            cmd_reg      <= cmd_next;
            tx_reg       <= tx_next;
            rx_reg       <= rx_next;
            divisor_reg  <= divisor_next;
            sda_out_reg  <= sda_out_next;
            scl_out_reg  <= scl_out_next;

            // Two-flop synchronizers
            scl_meta_reg <= scl_in;
            scl_sync_reg <= scl_meta_reg;
            sda_meta_reg <= sda_in;
            sda_sync_reg <= sda_meta_reg;

            // Short sample history
            scl_hist_reg <= {scl_hist_reg[1:0], scl_sync_reg};
            sda_hist_reg <= {sda_hist_reg[1:0], sda_sync_reg};

            // Previous filtered SDA value for stability check
            sda_filt_prev_reg <= sda_filt;

            // Watchdog counter
            high_wait_cnt_reg <= high_wait_cnt_next;

            // Sticky faults
            if (abort_fire)
            begin
                fault_abort_seen_reg <= 1'b1;
            end

            if (protocol_fault_event)
            begin
                fault_sda_unstable_reg <= 1'b1;
            end

            if (scl_high_timeout_event)
            begin
                fault_scl_high_timeout_reg <= 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // High-phase wait watchdog counter
    //
    // Counts only while waiting for qualified SCL-high.
    //--------------------------------------------------------------------------
    always_comb
    begin
        high_wait_cnt_next = high_wait_cnt_reg;

        if (waiting_for_high_phase)
        begin
            if (high_wait_cnt_reg != HIGH_WAIT_TIMEOUT_CLKS)
            begin
                high_wait_cnt_next = high_wait_cnt_reg + 1'b1;
            end
        end
        else
        begin
            high_wait_cnt_next = '0;
        end

        if (abort_fire)
        begin
            high_wait_cnt_next = '0;
        end
    end

    //--------------------------------------------------------------------------
    // Next-state logic
    //--------------------------------------------------------------------------
    always_comb
    begin
        state_next = state_reg;

        // Abort / recovery has priority over normal command flow
        if (abort_fire)
        begin
            state_next = S_ABORT_1;
        end
        else
        begin
            unique case (state_reg)
                S_IDLE:
                begin
                    if (idle_start_fire)
                    begin
                        state_next = S_START_1;
                    end
                end

                // START phase 1:
                // SDA low while SCL high.
                S_START_1:
                begin
                    if ((tick_cnt_reg == half_cnt_wide[DIVISOR_W-1:0]) && high_phase_ready)
                    begin
                        state_next = S_START_2;
                    end
                end

                // START phase 2:
                // pull SCL low and settle before HOLD.
                S_START_2:
                begin
                    if (tick_cnt_reg == quarter_cnt)
                    begin
                        state_next = S_HOLD;
                    end
                end

                // HOLD:
                // bus owned, SCL low, ready for next command.
                S_HOLD:
                begin
                    if (hold_restart_fire)
                    begin
                        state_next = S_RESTART;
                    end
                    else if (hold_stop_fire)
                    begin
                        state_next = S_STOP_1;
                    end
                    else if (hold_wr_fire || hold_rd_fire)
                    begin
                        state_next = S_DATA_1;
                    end
                end

                // RESTART:
                // release SCL/SDA as needed, then create a repeated START.
                S_RESTART:
                begin
                    if ((tick_cnt_reg == half_cnt_wide[DIVISOR_W-1:0]) && high_phase_ready)
                    begin
                        state_next = S_START_1;
                    end
                end

                // STOP phase 1:
                // release SCL high while SDA remains low.
                S_STOP_1:
                begin
                    if ((tick_cnt_reg == half_cnt_wide[DIVISOR_W-1:0]) && high_phase_ready)
                    begin
                        state_next = S_STOP_2;
                    end
                end

                // STOP phase 2:
                // release SDA high while SCL high.
                S_STOP_2:
                begin
                    if ((tick_cnt_reg == half_cnt_wide[DIVISOR_W-1:0]) && high_phase_ready)
                    begin
                        state_next = S_IDLE;
                    end
                end

                // DATA quarter 1:
                // SCL low, present next bit on SDA.
                S_DATA_1:
                begin
                    if (tick_cnt_reg == quarter_cnt)
                    begin
                        state_next = S_DATA_2;
                    end
                end

                // DATA quarter 2:
                // release SCL high and wait for confirmed-high.
                S_DATA_2:
                begin
                    if ((tick_cnt_reg == quarter_cnt) && high_phase_ready)
                    begin
                        state_next = S_DATA_3;
                    end
                end

                // DATA quarter 3:
                // stable high phase; actual SDA sample point lives here.
                S_DATA_3:
                begin
                    if ((tick_cnt_reg == quarter_cnt) && high_phase_ready)
                    begin
                        state_next = S_DATA_4;
                    end
                end

                // DATA quarter 4:
                // pull SCL low, then either continue to next bit or finish byte.
                S_DATA_4:
                begin
                    if (tick_cnt_reg == quarter_cnt)
                    begin
                        if (bit_idx_reg == BYTE_W)
                        begin
                            state_next = S_DATA_END;
                        end
                        else
                        begin
                            state_next = S_DATA_1;
                        end
                    end
                end

                // DATA_END:
                // extra low phase so byte completion aligns cleanly with HOLD.
                S_DATA_END:
                begin
                    if (tick_cnt_reg == quarter_cnt)
                    begin
                        state_next = S_HOLD;
                    end
                end

                // ABORT_1 / ABORT_2:
                // best-effort STOP-like cleanup path back to idle.
                S_ABORT_1:
                begin
                    if ((tick_cnt_reg == half_cnt_wide[DIVISOR_W-1:0]) && high_phase_ready)
                    begin
                        state_next = S_ABORT_2;
                    end
                end

                S_ABORT_2:
                begin
                    if ((tick_cnt_reg == half_cnt_wide[DIVISOR_W-1:0]) && high_phase_ready)
                    begin
                        state_next = S_IDLE;
                    end
                end

                default:
                begin
                    state_next = S_IDLE;
                end
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // Tick counter update
    //
    // Resets when:
    // - a legal command is accepted
    // - abort/recovery begins
    // - the current phase reaches its programmed time
    //--------------------------------------------------------------------------
    always_comb
    begin
        tick_cnt_next = tick_cnt_reg + 1'b1;

        if (cmd_fire || abort_fire)
        begin
            tick_cnt_next = '0;
        end

        if ((state_reg == S_START_1) || (state_reg == S_RESTART) ||
            (state_reg == S_STOP_1)  || (state_reg == S_STOP_2)  ||
            (state_reg == S_ABORT_1) || (state_reg == S_ABORT_2))
        begin
            if ((tick_cnt_reg == half_cnt_wide[DIVISOR_W-1:0]) && high_phase_ready)
            begin
                tick_cnt_next = '0;
            end
        end

        if ((state_reg == S_START_2) || (state_reg == S_DATA_1)   ||
            (state_reg == S_DATA_2)  || (state_reg == S_DATA_3)   ||
            (state_reg == S_DATA_4)  || (state_reg == S_DATA_END))
        begin
            if ((tick_cnt_reg == quarter_cnt) &&
                ((state_reg != S_DATA_2 && state_reg != S_DATA_3) || high_phase_ready))
            begin
                tick_cnt_next = '0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Latch divisor only when transaction starts from IDLE
    //--------------------------------------------------------------------------
    always_comb
    begin
        divisor_next = divisor_reg;

        if (idle_start_fire)
        begin
            divisor_next = divisor_clamped;
        end
    end

    //--------------------------------------------------------------------------
    // Latch command only when a legal command is accepted
    //--------------------------------------------------------------------------
    always_comb
    begin
        cmd_next = cmd_reg;

        if (cmd_fire)
        begin
            cmd_next = cmd;
        end
    end

    //--------------------------------------------------------------------------
    // Bit index update
    //
    // Reset at the start of WR/RD command.
    // Increment once per full bit transfer.
    //--------------------------------------------------------------------------
    always_comb
    begin
        bit_idx_next = bit_idx_reg;

        if (hold_wr_fire || hold_rd_fire)
        begin
            bit_idx_next = '0;
        end

        if ((state_reg == S_DATA_4) && (tick_cnt_reg == quarter_cnt))
        begin
            if (bit_idx_reg < BYTE_W)
            begin
                bit_idx_next = bit_idx_reg + 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // TX shift register
    //
    // WR:
    //   load 8-bit transmit data + dummy ACK slot
    //
    // RD:
    //   load zeros in data positions and rd_last_i into bit[0]
    //   so the 9th bit phase drives ACK/NACK from the master
    //--------------------------------------------------------------------------
    always_comb
    begin
        tx_next = tx_reg;

        if (hold_wr_fire)
        begin
            tx_next = {tx_data_i, 1'b1};
        end

        if (hold_rd_fire)
        begin
            tx_next = {{BYTE_W{1'b0}}, rd_last_i};
        end

        if ((state_reg == S_DATA_4) && (tick_cnt_reg == quarter_cnt))
        begin
            if (bit_idx_reg < BYTE_W)
            begin
                tx_next = {tx_reg[BYTE_W-1:0], 1'b0};
            end
        end
    end

    //--------------------------------------------------------------------------
    // RX shift register
    //
    // Sample later than V1.5:
    // - in S_DATA_3 instead of S_DATA_2
    // - after SCL has been qualified high
    // - using filtered SDA
    //--------------------------------------------------------------------------
    assign sample_sda_now =
        (state_reg == S_DATA_3) &&
        (tick_cnt_reg == quarter_cnt) &&
        high_phase_ready;

    always_comb
    begin
        rx_next = rx_reg;

        if (hold_wr_fire || hold_rd_fire)
        begin
            rx_next = '0;
        end

        if (sample_sda_now)
        begin
            rx_next = {rx_reg[BYTE_W-1:0], sda_filt};
        end
    end

    //--------------------------------------------------------------------------
    // SDA output control
    //
    // Convention:
    // - 1 -> release line (top-level should drive Z)
    // - 0 -> drive line low
    //
    // START/STOP/ABORT/HOLD states frame the bus.
    // DATA states drive the current TX bit.
    //--------------------------------------------------------------------------
    always_comb
    begin
        sda_out_next = 1'b1;

        if ((state_reg == S_START_1) || (state_reg == S_START_2) ||
            (state_reg == S_HOLD)    || (state_reg == S_DATA_END) ||
            (state_reg == S_STOP_1)  || (state_reg == S_ABORT_1))
        begin
            sda_out_next = 1'b0;
        end

        if ((state_reg == S_DATA_1) || (state_reg == S_DATA_2) ||
            (state_reg == S_DATA_3) || (state_reg == S_DATA_4))
        begin
            sda_out_next = tx_reg[BYTE_W];
        end
    end

    //--------------------------------------------------------------------------
    // SCL output control
    //
    // Convention:
    // - 1 -> release line (top-level should drive Z)
    // - 0 -> drive line low
    //--------------------------------------------------------------------------
    always_comb
    begin
        scl_out_next = 1'b1;

        if ((state_reg == S_START_2)  || (state_reg == S_HOLD)    ||
            (state_reg == S_DATA_1)   || (state_reg == S_DATA_4)  ||
            (state_reg == S_DATA_END) || (state_reg == S_ABORT_1))
        begin
            scl_out_next = 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // done tick
    //
    // Byte completion aligned with S_DATA_END completion.
    //--------------------------------------------------------------------------
    always_comb
    begin
        done_tick_int = 1'b0;

        if ((state_reg == S_DATA_END) && (tick_cnt_reg == quarter_cnt))
        begin
            done_tick_int = 1'b1;
        end
    end

    //--------------------------------------------------------------------------
    // Data phase / receiving flag
    //
    // Exported for top-level SDA tri-state behavior.
    //--------------------------------------------------------------------------
    assign data_phase =
        (state_reg == S_DATA_1) || (state_reg == S_DATA_2) ||
        (state_reg == S_DATA_3) || (state_reg == S_DATA_4);

    assign receiving_f =
        (data_phase && (cmd_reg == RD_CMD) && (bit_idx_reg < BYTE_W)) ||
        (data_phase && (cmd_reg == WR_CMD) && (bit_idx_reg == BYTE_W));

    //--------------------------------------------------------------------------
    // Outputs
    //--------------------------------------------------------------------------
    assign cmd_ready_o = (state_reg == S_IDLE) || (state_reg == S_HOLD);
    assign bus_idle_o  = (state_reg == S_IDLE);

    assign done_tick_o     = done_tick_int;
    assign ack_valid_o     = done_tick_int && (cmd_reg == WR_CMD);
    assign rd_data_valid_o = done_tick_int && (cmd_reg == RD_CMD);

    // rx_reg[8:1] = received byte
    // rx_reg[0]   = ACK bit captured during WR command
    assign rx_data_o = rx_reg[BYTE_W:1];
    assign ack_o     = rx_reg[0];

    assign sda_out = sda_out_reg;
    assign scl_out = scl_out_reg;

    assign master_receiving_o = receiving_f;

    // Sticky fault outputs
    assign fault_abort_seen_o       = fault_abort_seen_reg;
    assign fault_sda_unstable_o     = fault_sda_unstable_reg;
    assign fault_scl_high_timeout_o = fault_scl_high_timeout_reg;

    assign fault_any_o = fault_abort_seen_reg |
                         fault_sda_unstable_reg |
                         fault_scl_high_timeout_reg;

endmodule