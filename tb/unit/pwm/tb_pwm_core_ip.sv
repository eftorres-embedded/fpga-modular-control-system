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
task automatic wait_clks(input int n);
    repeat(n) @(posedge clk);
endtask

//Start meaurement at a clean period_end edge (avoid being inside a pulse
task automatic sync_to_period_end_edge();
    begin
        wait(!period_end);
        @(posedge period_end);
    end
endtask

//Measure clk cycles between consecutyve period_end pulses
task automatic expect_period_end_spacing(input int expected);
    int between;
        begin
            sync_to_period_end_edge();
            between = 0;

            fork    :   measure
                begin   : clk_counter
                    forever
                    begin
                        @(posedge clk);
                        between++;
                    end
                end

                begin   :   wait_next_pulse
                    wait (!period_end);
                    @(posedge period_end);
                end
            join_any

            disable measure;

            if(between != expected)
            begin
                $fatal(1, "FAIL: expected %0d cycles between period_end pulses, got %0d",
                        expected, between);
            end

            else
            begin
                $display("PASS: period_end spacing = %0d cycles", expected);
            end
        end
endtask

//Count number of cyles pwm_raw is high over ONE full effective period
//uses dut.period_cycles_eff (internal signal)
task automatic expect_pwm_highs_one_period(input int unsigned expected_highs);
    int unsigned highs;
    int unsigned i;
    int unsigned P;
    begin
        //Grab effective/clamped period from inside the DUT
        P   =   dut.period_cycles_eff;

        //Align to a boundary so we count exactly one period
        sync_to_period_end_edge();

        //Move to th first clk edge of the next period (cnt should be 0 after wrap)
        @(posedge clk);

        highs = 0;
        for(i=0; i<P; i++)
        begin
            //Sample pwm on each clk edge (stable for the full cycle)
            if(pwm_raw === 1'b1)
                highs++;
            @(posedge clk);
        end

        if(highs != expected_highs)
        begin
            $fatal(1, "FAIL: expected %0d highs in one period, got %0d (P=%0d)",
                    expected_highs, highs, P);
        end

        else
        begin
            $display("PASS: highs in one period = %0d (P=%0d)", highs, P);
        end
    end
endtask

//Drive enable on negedge to avoid smapling races at posedge
task automatic set_enable(input logic en);
    @(negedge clk);
    enable = en;
endtask

///////////////////////////////////////////////
//Test sequence
///////////////////////////////////////////////
initial begin
    $display("=== tb_pwm_core_ip start ===");

    //Init
    rst_n               =   1'b0;
    enable              =   1'b0;
    period_cycles_i     =   '0;
    duty_cycles_i       =   '0;
    use_default_duty    =   1'b0;

    //Reset
    wait_clks(5);
    rst_n   =   1'b1;
    wait_clks(2);

    //Enable PWM core
    set_enable(1'b1);

    //----------------------------------------
    //TEST 1: runtime period=10, duty=5 => 50%
    //----------------------------------------
    $display("TEST 1: period=10, duty=5 => expect spacing = 10, highs = 5");
    period_cycles_i     =   CNT_WIDTH'(10);
    use_default_duty    =   1'b0;
    duty_cycles_i       =   CNT_WIDTH'(5);
    
    expect_period_end_spacing(10);
    expect_pwm_highs_one_period(5);

    //----------------------------------------
    //TEST 2: duty=0 => always low 
    //-----------------------------------------
    $display("TEST 2: period=10, duty=0 => highs=0");
    duty_cycles_i = CNT_WIDTH'(0);
    expect_pwm_highs_one_period(0);

    //-----------------------------------------
    //TEST 3: duty=period => always high
    //-----------------------------------------
    $display("TEST 3: period=10, duty=10 => highs = 10");
    duty_cycles_i = CNT_WIDTH'(10);
    expect_pwm_highs_one_period(10);

    //-----------------------------------------
    //TEST 4: period=10, duty=999 => always high
    //-----------------------------------------
    $display("TEST 4: period=10, duty=999 => saturates => highs=10");
    duty_cycles_i   =   CNT_WIDTH'(999);
    expect_pwm_highs_one_period(10);

    //-----------------------------------------
    //TEST 5: period=0 => default period; default duty enabled
    //-----------------------------------------
    $display("TEST 5: period=0 -> default period = %0d; use default_duty => duty=%0d",
            TB_DEFAULT_PERIOD, TB_DEFAULT_DUTY);
    period_cycles_i     =   '0;
    use_default_duty    =   1'b1;
    duty_cycles_i       =   CNT_WIDTH'(123);

    //-----------------------------------------
    //TEST 6: period=1 -> timbase clamps to 2; 
    //-----------------------------------------
    $display("TEST 6: period=1 => clamp to 2 -> spacing=2");
    use_default_duty    = 1'b0;
    period_cycles_i     =   CNT_WIDTH'(1);
    duty_cycles_i       =   CNT_WIDTH'(1);

    expect_period_end_spacing(2);
    expect_pwm_highs_one_period(1);

    //-----------------------------------------
    //TEST 7: disable behavior: RST_CNT_WHEN_DISABLED=1 => resets, pwm low
    //------------------------------------------
    $display("TEST 7: disable => cnt=0 and pwm_raw=0");
    period_cycles_i =   CNT_WIDTH'(10);
    duty_cycles_i   =   CNT_WIDTH'(5);

    wait_clks(3);       //let cnt advance
    set_enable(1'b0);   //disable
    @(posedge clk);     //allow DUT to apply disable behavior
    @(negedge clk);
  
    if(cnt  !== '0)
        $fatal(1, "FAIL: expected pwm_raw==0 after disable, got %0d", cnt);
    if(pwm_raw !== 1'b0)
        $fatal(1, "FAIL: expected pwm_raw==0 after disable, got %0b", pwm_raw);
    $display("PASS: disable force cnt=0 and pwm_raw=0");

    $display("=== tb_pwm_core_ip PASS ===");
    $finish;
end

endmodule