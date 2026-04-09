// pwm_subsystem.sv
//
// Generic PWM subsystem top-level, V2 multi-channel version.
//
// -----------------------------------------------------------------------------
// Design intent
// -----------------------------------------------------------------------------
// This module is the integration layer between:
//
//   1) pwm_regs.sv   -> MMIO register/configuration block
//   2) pwm_core_ip.sv -> shared-timebase, multi-channel PWM generation core
//
// V2 keeps the same overall subsystem philosophy as V1:
//   - one bus-agnostic MMIO interface
//   - one shared PWM period/timebase
//   - shadow/active register model handled in pwm_regs
//
// The main V2 expansion is that the subsystem now exposes multiple PWM outputs,
// all running at the same frequency, but each with its own duty setting.
//
// -----------------------------------------------------------------------------
// Architectural choices worth remembering
// -----------------------------------------------------------------------------
// 1) pwm_subsystem remains a thin glue layer.
//    Reason: keep behavioral logic inside pwm_regs and pwm_core_ip.
//
// 2) cnt and period_end are still exposed.
//    Reason: these are useful for debug, testbenches, and notebook captures.
//
// 3) polarity and motor_ctrl are passed through from pwm_regs even though V2
//    does not yet implement motor-specific output logic in pwm_core_ip.
//    Reason: reserve the register/software contract now and leave room for V3.
//
// 4) CHANNELS is a synthesis-time parameter.
//    Reason: physical output count and register-bank width are structural, not
//    runtime-reconfigurable.
//

module pwm_subsystem #(
    parameter   int unsigned    ADDR_W      =   12,
    parameter   int unsigned    DATA_W      =   32,
    parameter   int unsigned    CNT_W       =   32,
    parameter   int unsigned    CHANNELS    =   4,
    parameter   bit APPLY_ON_PERIOD_END     =   1'b1)
    (
    input   logic               clk,
    input   logic               rst_n,

    //Generic MMIO request Channel
    input   logic                       req_valid,
    output  logic                       req_ready,
    input   logic                       req_write,
    input   logic   [ADDR_W-1:0]        req_addr,
    input   logic   [DATA_W-1:0]        req_wdata,
    input   logic   [(DATA_W/8)-1:0]    req_wstrb,

    //Generic MMIO response channel
    output  logic                       rsp_valid,
    input   logic                       rsp_ready,
    output  logic   [DATA_W-1:0]        rsp_rdata,
    output  logic                       rsp_err,

    //PWM outputs/debug
    output  logic   [CNT_W-1:0]         cnt,
    output  logic                       period_end,

    //Multichannel PWM outputs
    output  logic   [CHANNELS-1:0]      pwm_out);

    //--------------------------------------------------------------------------
    // Register block -> core configuration signals
    //--------------------------------------------------------------------------
    // These are the active configuration outputs from pwm_regs and the runtime
    // control inputs to pwm_core_ip.
    logic                   enable;
    logic   [CHANNELS-1:0]  ch_enable;
    logic                   use_default_duty;
    logic   [CNT_W-1:0]     period_cycles;
    logic   [CNT_W-1:0]     duty_cycles[CHANNELS];

    
    //----------------------------------------------------------------------------
    //V3 placeholders
    //----------------------------------------------------------------------------
    logic   [CHANNELS-1:0]  polarity;
    logic   [DATA_W-1:0]    motor_ctrl;

    pwm_regs    #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .CNT_W(CNT_W),
        .CHANNELS(CHANNELS),
        .APPLY_ON_PERIOD_END(APPLY_ON_PERIOD_END))
    u_pwm_regs(
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

        //Feedback from core for status and deferred APPLY behavior
        .period_end_i(period_end),
        .cnt_i(cnt),

        //Active configuration outputs
        .enable_o(enable),
        .use_default_duty_o(use_default_duty),
        .period_cycles_o(period_cycles),
        .duty_cycles_o(duty_cycles),

        //V3 placeholders
        .polarity_o(polarity),
        .motor_ctrl_o(motor_ctrl));


    //--------------------------------------------------------------------------
    // PWM generation core
    //--------------------------------------------------------------------------
    // Owns:
    // - shared timebase
    // - per-channel compare generation
    // - pwm_out vector
    //
    // V2 note:
    // polarity and motor_ctrl are intentionally not connected into core logic
    // yet. They are placeholders for V3 motor-control behavior such as
    // inversion, complementary outputs, and dead-time insertion.
    pwm_core_ip #(
        .CNT_WIDTH(CNT_W),
        .CHANNELS(CHANNELS))
    u_pwm_core_ip(
        .clk(clk),
        .rst_n(rst_n),

        .enable(enable),
        .ch_enable_i(ch_enable),
        .period_cycles_i(period_cycles),
        .duty_cycles_i(duty_cycles),

        .cnt(cnt),
        .period_end(period_end),
        .pwm_out(pwm_out));    

endmodule