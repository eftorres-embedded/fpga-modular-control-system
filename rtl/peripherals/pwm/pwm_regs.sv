//pwm_regs.sv
//
//Generic MMIO register file for PWM core.
//
//Features:
//-Bus-agnostic MMIO (req_valid/req_ready, rsp_valid/rsp_ready)
//-Shadow register for period/duty
//-APPLY bit (write 1) copies shadow register to active registers and auto-clears in hardware
// Optional boundary-sync of APPLY to period_end as a parameter

module pwm_regs #(
    parameter int unsigned ADDR_W   =   12, //enough for offsets
    parameter int unsigned DATA_W   =   32,
    parameter int unsigned CNT_W    =   32,

    //If 1: APPLY waits until period_end_i boefore updating active regs.
    //If 0: APPLY updates active regs immediately.
    parameter bit APPLY_ON_PERIOD_END   =   1'b0
)
(
    input   logic                       clk,
    input   logic                       rst_n,

    //--------------------------------------
    //----Generic MMIO request Channel
    //--------------------------------------
    input   logic                       req_valid,
    output  logic                       req_ready,
    input   logic                       req_write,      //1=write, 0=read
    input   logic   [ADDR_W-1:0]        req_addr,       //byte address
    input   logic   [DATA_W-1:0]        req_wdata,
    input   logic   [(DATA_W/8)-1:0]    req_wstrb,

    //---------------------------------------
    //----Generic MMIO response channel
    //---------------------------------------
    output  logic                       rsp_valid,
    input   logic                       rsp_ready,
    output  logic   [DATA_W-1:0]        rsp_rdata,
    output  logic                       rsp_err,   //1 = decode error

    //---------------------------------------
    //Interface signals to/from PWM  core
    //---------------------------------------
    input   logic                       period_end_i    //from core (one-cycle pulse)
    input   logic   [CNT_W-1:0]         cnt_i           //from core

    output  logic                       enable_o,
    output  logic                       use_default_duty_o,
    output  logic   [CNT_W-1:0]         period_cycles_o,
    output  logic   [CNT_W-1:0]         duty_cycles_o);

endmodule