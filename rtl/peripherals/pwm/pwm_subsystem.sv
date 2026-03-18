//pwm_subsystem.sv

module pwm_subsystem #(
    parameter   int unsigned    ADDR_W  =   12,
    parameter   int unsigned    DATA_W  =   32,
    parameter   int unsigned    CNT_W   =   32,
    parameter   bit APPLY_ON_PERIOD_END =   1'b1)
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
    output  logic   [CNT_W-1:0]     cnt,
    output  logic                       period_end,
    output  logic                       pwm_raw
    );

    logic                   enable;
    logic                   use_default_duty;
    logic   [CNT_W-1:0] period_cycles;
    logic   [CNT_W-1:0] duty_cycles;

    pwm_regs    #(
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .CNT_W(CNT_W),
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

        .period_end_i(period_end),
        .cnt_i(cnt),

        .enable_o(enable),
        .use_default_duty_o(use_default_duty),
        .period_cycles_o(period_cycles),
        .duty_cycles_o(duty_cycles));

    pwm_core_ip #(
        .CNT_WIDTH(CNT_W))
    u_pwm_core_ip(
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .period_cycles_i(period_cycles),
        .duty_cycles_i(duty_cycles),
        .cnt(cnt),
        .period_end(period_end),
        .pwm_raw(pwm_raw));    

endmodule