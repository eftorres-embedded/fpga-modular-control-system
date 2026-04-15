//pwm_subsystem_motor.sv
//
//H-bridge motor flavor of the PWM subsystem.
//
//-----------------------------------------------------------------------------
//Design intent
//-----------------------------------------------------------------------------
//This module integrates:
//
//  1) pwm_regs_common.sv      -> common PWM-family registers
//  2) pwm_regs_hbridge_ext.sv -> direction / brake / coast extension regs
//  3) pwm_core_ip.sv          -> shared-timebase, multichannel PWM generator
//  4) pwm_hbridge_adapter.sv  -> per-channel H-bridge output encoding
//
//This wrapper keeps the common PWM engine generic while adding motor-specific
//control through a small register extension and adapter layer.
//

module pwm_subsystem_motor #(
    parameter int unsigned ADDR_W       = 12,
    parameter int unsigned DATA_W       = 32,
    parameter int unsigned CNT_W        = 32,
    parameter int unsigned CHANNELS     = 4,
    parameter bit APPLY_ON_PERIOD_END   = 1'b1)
    (
    input   logic                       clk,
    input   logic                       rst_n,

    //-------------------------------------------------------------------------
    //Generic MMIO request channel
    //-------------------------------------------------------------------------
    input   logic                       req_valid,
    output  logic                       req_ready,
    input   logic                       req_write,
    input   logic   [ADDR_W-1:0]        req_addr,
    input   logic   [DATA_W-1:0]        req_wdata,
    input   logic   [(DATA_W/8)-1:0]    req_wstrb,

    //-------------------------------------------------------------------------
    //Generic MMIO response channel
    //-------------------------------------------------------------------------
    output  logic                       rsp_valid,
    input   logic                       rsp_ready,
    output  logic   [DATA_W-1:0]        rsp_rdata,
    output  logic                       rsp_err,

    //-------------------------------------------------------------------------
    //Debug / status
    //-------------------------------------------------------------------------
    output  logic   [CNT_W-1:0]         cnt,
    output  logic                       period_end,

    //-------------------------------------------------------------------------
    //H-bridge outputs
    //-------------------------------------------------------------------------
    output  logic   [CHANNELS-1:0]      pwm_o,
    output  logic   [CHANNELS-1:0]      in1_o,
    output  logic   [CHANNELS-1:0]      in2_o
);

    //-------------------------------------------------------------------------
    //Common regs -> PWM core signals
    //-------------------------------------------------------------------------
    logic                               enable;
    logic   [CHANNELS-1:0]              ch_enable;
    logic   [CNT_W-1:0]                 period_cycles;
    logic   [CNT_W-1:0]                 duty_cycles [CHANNELS];
    logic                               apply_commit;

    //-------------------------------------------------------------------------
    //H-bridge extension active signals
    //-------------------------------------------------------------------------
    logic   [CHANNELS-1:0]              dir_mask;
    logic   [CHANNELS-1:0]              brake_mask;
    logic   [CHANNELS-1:0]              coast_mask;

    //-------------------------------------------------------------------------
    //Raw PWM from core before H-bridge adaptation
    //-------------------------------------------------------------------------
    logic   [CHANNELS-1:0]              pwm_raw;

    //-------------------------------------------------------------------------
    //Common-register-block MMIO wiring
    //-------------------------------------------------------------------------
    logic                               common_req_valid;
    logic                               common_req_ready;
    logic                               common_rsp_valid;
    logic                               common_rsp_ready;
    logic   [DATA_W-1:0]                common_rsp_rdata;
    logic                               common_rsp_err;

    //-------------------------------------------------------------------------
    //H-bridge extension MMIO wiring
    //-------------------------------------------------------------------------
    logic                               ext_wr_en;
    logic                               ext_reg_hit;
    logic   [DATA_W-1:0]                ext_rdata;

    //-------------------------------------------------------------------------
    //Top-level response tracking
    //-------------------------------------------------------------------------
    logic                               pending_common;
    logic                               ext_rsp_valid_reg;
    logic   [DATA_W-1:0]                ext_rsp_rdata_reg;
    logic                               ext_rsp_err_reg;

    logic                               idle;
    logic                               route_to_ext;
    logic                               req_fire;

    assign  idle         = !pending_common && !ext_rsp_valid_reg;

    //H-bridge extension only owns its exact registers.
    //All other addresses route to the common block.
    assign route_to_ext = ext_reg_hit;

    //-------------------------------------------------------------------------
    //Request routing
    //-------------------------------------------------------------------------
    //Only one outstanding transaction at a time at the subsystem level.
    //subsystem must be idle &&
    //
    //If the address belongs to the H-bridge extension:
    // - the subsystem handles the response locally
    //
    //Otherwise:
    // - forward request to pwm_regs_common
    assign req_ready = idle && (route_to_ext ? 1'b1 : common_req_ready);
    assign req_fire  = req_valid && req_ready;

    assign common_req_valid = req_valid && idle && !route_to_ext;
    assign common_rsp_ready = pending_common && rsp_ready;

    assign ext_wr_en = req_fire && route_to_ext && req_write;

    //-------------------------------------------------------------------------
    //Common register block
    //-------------------------------------------------------------------------
    pwm_regs_common #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .CNT_W(CNT_W),
        .CHANNELS(CHANNELS),
        .APPLY_ON_PERIOD_END(APPLY_ON_PERIOD_END))
        
    u_pwm_regs_common(
        .clk(clk),
        .rst_n(rst_n),

        .req_valid(common_req_valid),
        .req_ready(common_req_ready),
        .req_write(req_write),
        .req_addr(req_addr),
        .req_wdata(req_wdata),
        .req_wstrb(req_wstrb),

        .rsp_valid(common_rsp_valid),
        .rsp_ready(common_rsp_ready),
        .rsp_rdata(common_rsp_rdata),
        .rsp_err(common_rsp_err),

        .period_end_i(period_end),
        .cnt_i(cnt),

        .enable_o(enable),
        .ch_enable_o(ch_enable),
        .period_cycles_o(period_cycles),
        .duty_cycles_o(duty_cycles),

        .apply_commit_o(apply_commit)
    );

    //-------------------------------------------------------------------------
    //H-bridge extension register slice
    //-------------------------------------------------------------------------
    pwm_regs_hbridge_ext #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .CHANNELS(CHANNELS))
    u_pwm_regs_hbridge_ext(
        .clk(clk),
        .rst_n(rst_n),

        .wr_en(ext_wr_en),
        .addr(req_addr),
        .wdata(req_wdata),
        .wstrb(req_wstrb),

        .apply_commit_i(apply_commit),

        .reg_hit_o(ext_reg_hit),
        .rdata_o(ext_rdata),

        .dir_mask_o(dir_mask),
        .brake_mask_o(brake_mask),
        .coast_mask_o(coast_mask)
    );

    //-------------------------------------------------------------------------
    //Common PWM generator
    //-------------------------------------------------------------------------
    pwm_core_ip #(
        .CNT_WIDTH(CNT_W),
        .CHANNELS(CHANNELS)
    ) u_pwm_core_ip (
        .clk(clk),
        .rst_n(rst_n),

        .enable(enable),
        .ch_enable_i(ch_enable),
        .period_cycles_i(period_cycles),
        .duty_cycles_i(duty_cycles),

        .cnt(cnt),
        .period_end(period_end),
        .pwm_o(pwm_raw)
    );

    //-------------------------------------------------------------------------
    //Per-channel H-bridge adapters
    //-------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < CHANNELS; i++)
        begin : g_hbridge
            pwm_hbridge_adapter u_pwm_hbridge_adapter
            (
                .direction_i(dir_mask[i]),
                .brake_i(brake_mask[i]),
                .coast_i(coast_mask[i]),
                .pwm_i(pwm_raw[i]),

                .pwm_o(pwm_o[i]),
                .in1_o(in1_o[i]),
                .in2_o(in2_o[i])
            );
        end
    endgenerate

    //-------------------------------------------------------------------------
    //Subsystem-owned response path for extension accesses
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            pending_common      <= 1'b0;
            ext_rsp_valid_reg   <= 1'b0;
            ext_rsp_rdata_reg   <= '0;
            ext_rsp_err_reg     <= 1'b0;
        end
        else
        begin
            //Clear local extension response after handshake
            if (ext_rsp_valid_reg && rsp_ready && !pending_common)
            begin
                ext_rsp_valid_reg <= 1'b0;
            end

            //Track common-path outstanding request
            if (req_fire && !route_to_ext)
            begin
                pending_common <= 1'b1;
            end
            else if (pending_common && common_rsp_valid && rsp_ready)
            begin
                pending_common <= 1'b0;
            end

            //Create one response for extension accesses
            if (req_fire && route_to_ext)
            begin
                ext_rsp_valid_reg <= 1'b1;
                ext_rsp_rdata_reg <= ext_rdata;
                ext_rsp_err_reg   <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    //Unified response mux
    //-------------------------------------------------------------------------
    assign rsp_valid = pending_common ? common_rsp_valid : ext_rsp_valid_reg;
    assign rsp_rdata = pending_common ? common_rsp_rdata : ext_rsp_rdata_reg;
    assign rsp_err   = pending_common ? common_rsp_err   : ext_rsp_err_reg;

endmodule