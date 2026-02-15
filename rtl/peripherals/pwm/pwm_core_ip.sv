//pwm_core.sv
//Core wrapper: applies DEFAULT_PERIOD_CYCLES when period_i == 0;
//provs cnt, period_end, and pwm_raw
module pwm_core_ip #(
    parameter int unsigned CNT_WIDTH                =   32,
    parameter int unsigned DEFAULT_PERIOD_CYCLES    =   32'd5_000,
    parameter int unsigned DEFUALT_DUTY_CYCLES      =   32'd2_500
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


assign period_active    = (period_cycles == 0)  ? DEFAULT_PERIOD_CYCLES : period_cycles_i;
assign duty_active      = use_default_duty      ? DEFAULT_DUTY_CYCLES   : duty_cycles_i;

pwm_timebase    #(
        .CNT_WIDTH(CNT_WIDTH),
        .DEFAULT_PERIOD_CYCLES(DEFAULT_PERIOD_CYCLES),
        .RST_CNT_WHEN_DISABLED()
    )
    u_timebase(
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .period_cycles(period_active),
        .cnt(cnt),
        .period_start(),
        .period_end(period_end)
    );

pwm_compare     #(
        .CNT_WIDTH(CNT_WIDTH),
    )
    u_pwmcompare(
        .enable(enable),
        .cnt(cnt),
        .period_cycles_eff(period_active),
        .duty_cycles(duty_active),
        .pwm_raw(pwm_raw)
    );
    

endmodule