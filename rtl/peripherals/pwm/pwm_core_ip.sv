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

endmodule