//pwm_core_ip.sv
//
//v2 multi-channel PWM core
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
    parameter int unsigned CHANNELS                 =   4,
    parameter int unsigned DEFAULT_PERIOD_CYCLES    =   32'd5_000)
(
   input    logic               clk,
   input    logic               rst_n,
   
   //Global enable
   //If this is low, the shared timmebase is disable and all outputs are forced low
   input    logic               enable,

   //Per-channel output enable mask
   //Bit i enables/disables "channel i" independently
   //all still share same timebase and period
   input    logic   [CHANNELS-1:0]  ch_enable_i,
   
   //Global runtime period
   //If sofware writes 0, the core falls back to DEFAULT_PERIOD_CYCLES
   input    logic   [CNT_WIDTH-1:0] period_cycles_i,

   //Per-channel runtime duty values
   //duty_cycles_i[i] is the requested duty in clock cycles for "channel i"
   input    logic   [CNT_WIDTH-1:0] duty_cycles_i[CHANNELS],


    //Global timebase visibility/debug
   output   logic   [CNT_WIDTH-1:0] cnt,
   output   logic                   period_end,

   //Muli-channel Pwm outputs
   //Still "pure PWM" outputs in V2, no motor-specific post-processing
   output   logic   [CHANNELS-1:0]  pwm_out
);

//------------------------------------------------------------------------
//Internal signals
//-----------------------------------------------------------------------

//Shared active period that will be fed into the timebase
//This is the runtime period unless fotware supplied 0.
logic   [CNT_WIDTH-1:0] period_active;

//Effective period after timbebase-side safty clamping.
//pwm_timebase guarantees this will not be an illegal value such as 0 or 1
logic   [CNT_WIDTH-1:0] period_cycles_eff;

//This lets pwm_compare remain unchaged from V1: it still sees a simple
//single-bit enable input
logic   [CHANNELS-1:0]  ch_enable_eff;

//Shared period selection
//if software provides a period of 0, the core uses a known default period
//the timebase will still clamp unsafe small values internally
assign  period_active   = (period_cycles_i == '0)
                        ? CNT_WIDTH'(DEFAULT_PERIOD_CYCLES)
                        : period_cycles_i;

assign  ch_enable_eff   =   {CHANNELS{enable}}  & ch_enable_i;


//-----------------------------------------------------------------------
//Shared PWM timebase
//-----------------------------------------------------------------------
//One counter is shared by all channels
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

//-----------------------------------------------------------------------
//Per-channel compare bank
//-----------------------------------------------------------------------
//
//Reuse pwm_compare exactly as in V1. Each instance:
// - Sees the shared counter
// - sees the shared effective period
// - gets its own duty setting
// - gets its own effective enable
//
//  This keeps the architecture incremental and makes verification easier.

genvar  i;
generate
    for(i=0; i<CHANNELS; i++)
    begin   :   g_pwm_compare
        pwm_compare     #(
            .CNT_WIDTH(CNT_WIDTH)
        )
        u_pwmcompare(
            .enable(ch_enable_ff[i]),
            .cnt(cnt),
            .period_cycles_eff(period_cycles_eff),
            .duty_cycles(duty_cycles_i[i]),
            .pwm_raw(pwm_out[i])
        );
    end
endgenerate
    

endmodule