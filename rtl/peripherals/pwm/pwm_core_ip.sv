//pwm_core_ip.sv
//Core wrapper: applies DEFAULT_PERIOD_CYCLES when period_i == 0;
//provides cnt, period_end, and pwm_raw
//
//Purpose
//-Glue layer that composes the PWM subsystem from two reusable blocks:
//  1) pwm_timebase : generates a period counter and period boundary pulses
//  2) pwm_compare  : generates pwm_raw via (cnt < duty_eff)
//
//What this block does:
//-Selects an active PWM period:
//  -If period_cycles_i == 0, use DEFAULT_PERIOD_CYCLES
//  -Otherwise use period_cycles_i
//-Selects an active duty:
//  -If use_default_duty == 1, use DEFAULT_DUTY_CYCLES
//  -Otherwise use duty_cycles_i
//
//Outputs
//-cnt          :  free-running counter from timebase (wraps at effective period)
//-period_end   : one-clock pulse at end of each PWM period
//-pwm_raw      : raw PWM signal (pre-mode processing)

module pwm_core_ip #(
    parameter int unsigned CNT_WIDTH                =   32,
    parameter int unsigned DEFAULT_PERIOD_CYCLES    =   32'd5_000,
    parameter int unsigned DEFAULT_DUTY_CYCLES      =   32'd2_500
)
(
   input    logic               clk,
   input    logic               rst_n,
   input    logic               enable,

   //Runtime overwrites
   input    logic   [CNT_WIDTH-1:0] period_cycles_i,
   input    logic   [CNT_WIDTH-1:0] duty_cycles_i,

   //use default duty
   input    logic                   use_default_duty,

   output   logic   [CNT_WIDTH-1:0] cnt,
   output   logic                   period_end,
   output   logic                   pwm_raw
);

logic   [CNT_WIDTH-1:0] period_active;
logic   [CNT_WIDTH-1:0] duty_active;
logic   [CNT_WIDTH-1:0] period_cycles_eff;


assign period_active    = (period_cycles_i == '0)   ? CNT_WIDTH'(DEFAULT_PERIOD_CYCLES) : period_cycles_i;
assign duty_active      = use_default_duty          ? CNT_WIDTH'(DEFAULT_DUTY_CYCLES)   : duty_cycles_i;

pwm_timebase    #(
        .CNT_WIDTH(CNT_WIDTH),
        .DEFAULT_PERIOD_CYCLES(CNT_WIDTH'(DEFAULT_PERIOD_CYCLES)),
        .RST_CNT_WHEN_DISABLED(1)
    )
    u_timebase(
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .period_cycles(period_active),
        .cnt(cnt),
        .period_start(),
        .period_end(period_end),
        .period_cycles_eff(period_cycles_eff)
    );

pwm_compare     #(
        .CNT_WIDTH(CNT_WIDTH)
    )
    u_pwmcompare(
        .enable(enable),
        .cnt(cnt),
        .period_cycles_eff(period_cycles_eff),
        .duty_cycles(duty_active),
        .pwm_raw(pwm_raw)
    );
    

endmodule