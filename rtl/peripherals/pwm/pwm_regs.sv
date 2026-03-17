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


    //------------------------------------------------
    //Register offsets (byte)
    //------------------------------------------------
    localparam  logic   [ADDR_W-1:0]    REG_CTRL    =   'h00;
    localparam  logic   [ADDR_W-1:0]    REG_PERIOD  =   'h04;
    localparam  logic   [ADDR_W-1:0]    REG_DUTY    =   'h08;
    localparam  logic   [ADDR_W-1:0]    REG_STATUS  =   'h0C;
    localparam  logic   [ADDR_W-1:0]    REG_CNT     =   'h10;

    //------------------------------------------------
    //Internal state: Shadow + active
    //------------------------------------------------
    logic               enable_shadow;
    logic               use_default_shadow;
    logic   [CNT_W-1:0] period_shadow;
    logic   [CNT_W-1:0] duty_shadow;

    logic               enable_active;
    logic               use_default_active;
    logic   [CNT_W-1:0] period_active;
    logic   [CNT_W-1:0] duty_active;

    //APPLY handling
    logic               apply_pulse;    //one-cycle internal stobe when SW writes apply=1
    logic               apply_pending   //if boundary sync enabled

    //Response buffering (1 level deep)
    logic                   accept_req;
    logic   [DATA_W-1:0]    rdata_next;
    logic                   err_next;

    //-------------------------------------------------
    //Ready/valid: single outstanding response
    //req_ready is deasserted if we still owe a response and rsp_ready is low
    //-------------------------------------------------
    assign  req_ready   =   (!rsp_valid)    ||  (rsp_valid && rsp_ready);
    assign  accept_req  =   req_valid   &&  req_ready;

    //Helper function: byte-write merge for 32-bit regs
    function    automatic   logic   [DATA_W-1:0]    merge_wstrb( //merge write-strobe-bit
        input   logic   [DATA_W-1:0]    old_val,
        input   logic   [DATA_W-1:0]    new_val,
        input   logic   [(DATA_W/8)-1:0] strb);                 //byte aligned

        logic [DATA_W-1]    write_mask;
        begin
            write_mask  =   {
                {8{strb[3]}},
                {8{strb[2]}},
                {8{strb[1]}},
                {8{strb[0]}}
            };

            return (old_val & ~write_mask) | (new_val & write_mask);
        end
    endfunction

    //--------------------------------------------------
    // Read Mux 
    //--------------------------------------------------
    always_comb
    begin
        rdata_next  =   '0;
        err_next    =   1'b0;

        unique  case(req_addr)

            REG_CTRL: begin
                rdata_next[0]   =   enable_active;
                rdata_next[1]   =   use_def_active;
                rdata_next[3]   =   1'b0;
            end

            REG_PERIOD: begin
                rdata_next  =   period_shadow;
            end

            REG_DUTY:   begin
                rdata_next  =   duty_shadow;
            end

            REG_STATUS: begin
                rdata_next[0]   =   period_end_i;
                rdata_next[1]   =   apply_pending;
            end

            REG_CNT:    begin
                rdata_next  =   cnt_i;
            end

            default:    begin
                rdata_next  =   '0;
                err_next    =   1'b1;   //decode error
            end
        endcase
    end

    





endmodule