`timescale 1ns/1ps

module tb_pwm_core_ip;

//////////////////////////////////////////////
//Local params (TB-scale values for visibility
//////////////////////////////////////////////
localparam int unsigned CNT_WIDTH = 32;

//Make defaults small to see activity easily
localparam int unsigned TB_DEFAULT_PERIOD   = 20;
localparam int unsigned TB_DEFAULT_DUTY     = 7;


//////////////////////////////////////////////
//DUT inputs
//////////////////////////////////////////////
logic               clk;
logic               rst_n;
logic               enable;

logic   [CNT_WIDTH-1:0] period_cycles_i;
logic   [CNT_WIDTH-1:0] duty_cycles_i;
logic                   use_default_duty;

//////////////////////////////////////////////
//DUT outputs
//////////////////////////////////////////////
logic   [CNT_WIDTH-1:0] cnt;
logic                   period_end;
logic                   pwm_raw;

//////////////////////////////////////////////
//Clock: 50 MHz (20ns period)
//////////////////////////////////////////////
initial clk = 1'b0;
always #10 clk = ~clk;

//////////////////////////////////////////////
//DUT instance
//////////////////////////////////////////////
pwm_core_ip #(
    .CNT_WIDTH(CNT_WIDTH),
    .DEFAULT_PERIOD_CYCLES(TB_DEFAULT_PERIOD),
    .DEFAULT_DUTY_CYCLES(TB_DEFAULT_DUTY)
)
    dut(
    .clk(clk),
    .rst_n(rst_n),
    .enable(enable),
    .period_cycles_i(period_cycles_i),
    .duty_cycles_i(duty_cycles_i),
    .use_default_duty(use_default_duty),
    .cnt(cnt),
    .period_end(period_end),
    .pwm_raw(pwm_raw)
    );

////////////////////////////////////////////////
//helpers
////////////////////////////////////////////////
task automatic wait_clks();

endtask

//Start meaurement at a clean period_end edge (avoid being inside a pulse
task automatic sync_to_period_end_edge();
endtask

//Measure clk cycles between consecutyve period_end pulses
task automatic expect_period_end_spacing();
endtask

//Count number of cyles pwm_raw is high over ONE full effective period
//uses dut.period_cycles_eff (internal signal)
task automatic expect_pwm_highs_one_period();
endtask

//Drive enable on negedge to avoid smapling races at posedge
task automatic set_enable();
endtask

///////////////////////////////////////////////
//Test sequence
///////////////////////////////////////////////

endmodule