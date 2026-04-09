//pwm_regs.sv
//
//Generic MMIO register file for PWM core, V2 multi-channel version.
//
//-----------------------------------------------------------------------------
//Design intent
//-----------------------------------------------------------------------------
//This module is still the register/configuration layer of the PWM subsystem.
//V2 is intentionally an incremental extension of V1, not a redesign.
//
//The choices preserved from V1 are:
//  - bus-agnostic MMIO interface
//  - shadow registers written by software
//  - active registers consumed by hardware
//  - explicit REG_APPLY commit mechanism
//  - optional deferred commit at PWM period boundary
//
//The main V2 change is scaling from one duty register to CHANNELS duty registers,
//while keeping one shared period and one shared timebase.
//
//-----------------------------------------------------------------------------
//Architectural choices worth remembering
//-----------------------------------------------------------------------------
//1) CTRL remains a full DATA_W register.
//   Reason: this matches V1 style, keeps MMIO behavior normal, supports
//   merge_wstrb() cleanly, and leaves room for future control bits.
//
//2) DUTY registers are banked starting at 0x20 using:
//      REG_DUTY[i] = REG_DUTY_BASE + 4*i
//   Reason: simple software model, simple decode, natural 32-bit spacing.
//
//3) Shadow registers are what software reads back.
//   Reason: software should see what it last configured, even before APPLY.
//
//4) REG_POLARITY and REG_MOTOR_CTRL are placeholders in V2.
//   Reason: reserve addresses now so V3 does not require a disruptive remap.
//
//5) APPLY can be immediate or boundary-synchronized.
//   Reason: preserve V1 glitch-free update model and startup-safe behavior.
//
//
//Assumption for V2:
//- MMIO register width is 32 bits
//- Channel bitmask registers (REG_CH_ENABLE, REG_POLARITY) are also 32 bits
//- Therefore CHANNELS must be <= DATA_W, and in normal use DATA_W = 32

module pwm_regs #(
    parameter   int unsigned    ADDR_W      =   12,
    parameter   int unsigned    DATA_W      =   32,
    parameter   int unsigned    CNT_W       =   32,
    parameter   int unsigned    CHANNELS    =   4,

    //If 1: APPLY waits until period_end_i before updating active regs,
    //unless startup/inactive bypass is needed.
    //If 0: APPLY updates active regs immediately.
    parameter   bit APPLY_ON_PERIOD_END =   1'b1)
(
    input   logic                       clk,
    input   logic                       rst_n,

    //--------------------------------------
    //Generic MMIO request channel
    //--------------------------------------
    input   logic                       req_valid,
    output  logic                       req_ready,
    input   logic                       req_write,      //1=write, 0=read
    input   logic   [ADDR_W-1:0]        req_addr,       //byte address
    input   logic   [DATA_W-1:0]        req_wdata,
    input   logic   [(DATA_W/8)-1:0]    req_wstrb,

    //---------------------------------------
    //Generic MMIO response channel
    //---------------------------------------
    output  logic                       rsp_valid,
    input   logic                       rsp_ready,
    output  logic   [DATA_W-1:0]        rsp_rdata,
    output  logic                       rsp_err,        //1 = decode error

    //---------------------------------------
    //Interface signals to/from PWM core
    //---------------------------------------
    //Status from PWM core
    input   logic                       period_end_i,   //one-cycle pulse from core
    input   logic   [CNT_W-1:0]         cnt_i,          //live counter from core

    //Active configuration outputs to PWM_CORE
    output  logic                       enable_o,
    output  logic   [CHANNELS-1:0]      ch_enable_o,
    output  logic   [CNT_W-1:0]         period_cycles_o,
    output  logic   [CNT_W-1:0]         duty_cycles_o   [CHANNELS],
    
    //-----------------------------------------
    //Placeholder outputs for future V3 motor features
    //-----------------------------------------
    output  logic   [CHANNELS-1:0]      polarity_o,
    output  logic   [DATA_W-1:0]        motor_ctrl_o);

    //V2 sizing assumption:
    //This register block uses 32-bit MMIO words and 32-bit channel mask registers.
    //For that reason, CHANNELS is expected to be 32 or less.
    //That is sufficient for the intended use cases (motors / LEDs) and keeps the
    //register model simple. You can always instantiage more PWM modules if you need
    //more pwm signals and coordinat them in software. 
    initial 
    begin
        if (CHANNELS > DATA_W)
        begin
            $error("pwm_regs: CHANNELS (%0d) must be <= DATA_W (%0d)", CHANNELS, DATA_W);
        end
    end

    //------------------------------------------------
    //Register offsets (byte)
    //------------------------------------------------
    localparam  logic   [ADDR_W-1:0]    REG_CTRL        =   'h00;
    localparam  logic   [ADDR_W-1:0]    REG_PERIOD      =   'h04;
    localparam  logic   [ADDR_W-1:0]    REG_APPLY       =   'h08;
    localparam  logic   [ADDR_W-1:0]    REG_CH_ENABLE   =   'h0C;
    localparam  logic   [ADDR_W-1:0]    REG_STATUS      =   'h10;
    localparam  logic   [ADDR_W-1:0]    REG_CNT         =   'h14;
    localparam  logic   [ADDR_W-1:0]    REG_POLARITY    =   'h18;   //placeholder for V3
    localparam  logic   [ADDR_W-1:0]    REG_MOTOR_CTRL  =   'h1C;   //placeholder for V3
    //------------------------------------------------
    //Base of banked duty register region (one per channel)
    //REG_DUTY[i]   =   REG_DUTY_BASE + 4*i
    //------------------------------------------------
    localparam  logic   [ADDR_W-1:0]    REG_DUTY_BASE   =   'h20;

    //------------------------------------------------
    //Internal state: shadow + active
    //------------------------------------------------
    //shadow
	logic   [DATA_W-1:0]    ctrl_shadow;
    logic   [CNT_W-1:0]     period_shadow;
    logic   [CNT_W-1:0]     duty_shadow[CHANNELS];
    logic   [CHANNELS-1:0]  ch_enable_shadow;
    //placeholder for V3
    logic   [CHANNELS-1:0]  polarity_shadow;
    logic   [DATA_W-1:0]    motor_ctrl_shadow;
    
    //active
	logic   [DATA_W-1:0]    ctrl_active;
    logic   [CNT_W-1:0]     period_active;
    logic   [CNT_W-1:0]     duty_active[CHANNELS];
    logic   [CHANNELS-1:0]  ch_enable_active;
    //placeholder for V3
    logic   [CHANNELS-1:0]  polarity_active;
    logic   [DATA_W-1:0]    motor_ctrl_active;



    //------------------------------------------------
    //APPLY handling
    //------------------------------------------------
    logic                   apply_pulse;         //one-cycle pulse when SW writes REG_APPLY[0]=1
    logic                   apply_pending;       //pending deferred commit
    logic                   safe_to_delay_apply; //active PWM already running
    logic                   apply_commit_now;    //commit shadow -> active this cycle

    //------------------------------------------------
    //Request / Response control signals
    //------------------------------------------------
    logic                   req_fire;
    logic   [DATA_W-1:0]    rdata_next;
    logic                   err_next;
    logic                   rsp_fire;


    //------------------------------------------------------------------
    //Duty-bank addresss decode signals
    //------------------------------------------------------------------
    logic           duty_addr_hit; //is the MMIO address one of the REG_DUTY[i] addresses?
    int unsigned    duty_idx;       //converts the REG_DUTY[i] address to its pwm_out channel: channel 1, 2, 3...
    

    //-------------------------------------------------
    //Ready/valid: single outstanding response
    //-------------------------------------------------
    assign  rsp_fire    =   rsp_valid && rsp_ready;
    assign  req_ready   =   (!rsp_valid) || (rsp_fire);
    assign  req_fire    =   req_valid && req_ready;
    

    //-------------------------------------------------
    //Helper function: byte-write merge for 32-bit regs
    //-------------------------------------------------
    function automatic logic [DATA_W-1:0] merge_wstrb(
        input   logic   [DATA_W-1:0]        old_val,
        input   logic   [DATA_W-1:0]        new_val,
        input   logic   [(DATA_W/8)-1:0]    strb);
		  
        logic [DATA_W-1:0] write_mask;
        begin
            write_mask = {
                {8{strb[3]}},
                {8{strb[2]}},
                {8{strb[1]}},
                {8{strb[0]}}
            };

            return (old_val & ~write_mask) | (new_val & write_mask);
        end
    endfunction

    //----------------------------------------------------------------
    //Duty-bank address decode
    //----------------------------------------------------------------
    //REG_DUTY[I]   =   REG_DUTY_BASE   + 4*I
    //
    //Valid duty address must:
    // - start at REG_DUTY_BASE
    // - stay within CHANNELS*4 bytes
    // - be word aligned
    always_comb
    begin
        duty_addr_hit   =   1'b0;
        duty_idx        =   0;

        if( (req_addr >= REG_DUTY_BASE) &&
            (req_addr <  (REG_DUTY_BASE + CHANNELS*4)) &&
            (req_addr[1:0]  ==  2'b00))
        begin
            duty_addr_hit   =   1'b1;
            duty_idx        =   (req_addr   -   REG_DUTY_BASE) >> 2;
        end
    end


    //--------------------------------------------------
    //Read mux
    //--------------------------------------------------
    //Read back shadow duty values, because sofware should see the
    //configuration it has most recently written, not only what has 
    //already been aplied to the hardware
    always_comb 
	begin
        rdata_next = '0;
        err_next   = 1'b0;

        if(duty_addr_hit)
        begin
            rdata_next  =   duty_shadow[duty_idx];
        end

        else
        begin

            unique case (req_addr)

                REG_CTRL:
                begin
                    //Read back SHADOW control bits like a normal RW register
                    rdata_next = ctrl_shadow; //enable_shadow;
                end

                REG_PERIOD:
                begin
                    rdata_next = period_shadow;
                end

                REG_CH_ENABLE:
                begin
                    rdata_next  =   '0; //Channels might be less than 32 bit, this makes sure to clear all unused bits
                    rdata_next[CHANNELS-1:0]    =   ch_enable_shadow;
                end

                REG_APPLY:
                begin
                    //Command register: read as 0
                    rdata_next = '0;
                end

                REG_STATUS:
                begin
                    rdata_next[0] = period_end_i;
                    rdata_next[1] = apply_pending;
                    rdata_next[2] = ctrl_active[0]; //active global enable
                end

                REG_CNT:
                begin
                    rdata_next = cnt_i;
                end

                REG_POLARITY:
                begin
                    rdata_next  =   '0;
                    rdata_next[CHANNELS-1:0]    =   polarity_shadow;
                end

                REG_MOTOR_CTRL:
                begin
                    rdata_next  =   motor_ctrl_shadow;
                end

                default:
                begin
                    rdata_next = '0;
                    err_next   = 1'b1;
                end
            endcase
        end
    end

    //-------------------------------------------------
    //APPLY pulse detection
    //REG_APPLY bit[0] is write-one-to-apply
    //-------------------------------------------------
    always_comb
	begin
        apply_pulse = 1'b0;

        if(req_fire && req_write && (req_addr == REG_APPLY))
		begin
            if(req_wstrb[0] && req_wdata[0])
                apply_pulse = 1'b1;
        end
    end

    //---------------------------------------------------
    //Deferred/immediate APPLY control
    //---------------------------------------------------
    always_comb
	begin
        //Defer only when PWM is already active and has a valid active period.
        //This avoids startup deadlock when APPLY_ON_PERIOD_END=1.
        safe_to_delay_apply = ctrl_active[0] && (period_active != '0);
        apply_commit_now = 1'b0;

        if(APPLY_ON_PERIOD_END)
		begin
            if(apply_pulse || apply_pending)
			begin
                if(!safe_to_delay_apply)
                    apply_commit_now = 1'b1;   //startup/inactive bypass
                else if(period_end_i)
                    apply_commit_now = 1'b1;   //normal synchronized commit
            end
        end
		  
        else
		begin
            apply_commit_now = apply_pulse;    //immediate mode
        end
    end

    //----------------------------------------------------------
    //sequential logic
    //----------------------------------------------------------
    integer k;
    always_ff @(posedge clk or negedge rst_n)
	begin
        if(!rst_n)
		begin
            ctrl_shadow		    <=  '0;
            ch_enable_shadow    <=  '0;
            period_shadow	    <=  '0;
            polarity_shadow     <=  '0;
            motor_ctrl_shadow   <=  '0;

            for(k=0; k<CHANNELS; k++)
            begin
                duty_shadow[k]  <=  '0;
                duty_active[k]  <=  '0;
            end
            
            ctrl_active		    <=  '0;
            ch_enable_active    <=  '0;
            period_active	    <=  '0;
            polarity_active     <=  '0;
            motor_ctrl_active   <=  '0;
            
            apply_pending	<=  1'b0;

            rsp_valid		<=  1'b0;
            rsp_rdata		<=  '0;
            rsp_err			<=  1'b0;
        end
		  
        else
		begin
            //--------------------------------------------
            //Response channel clear
            //--------------------------------------------
            if (rsp_fire)
            begin
                rsp_valid <= 1'b0;
            end

            //--------------------------------------------
            //APPLY commit path
            //--------------------------------------------
            if(apply_commit_now)
			begin
                ctrl_active		    <=  ctrl_shadow;
                ch_enable_active    <=  ch_enable_shadow;
                period_active	    <=  period_shadow;
                polarity_active     <=  polarity_shadow;
                motor_ctrl_active   <=  motor_ctrl_shadow;
                
                for(k=0;k<CHANNELS;k++)
                begin
                    duty_active[k] <= duty_shadow[k];
                end

                apply_pending	    <=  1'b0;
            end

            else if(apply_pulse && APPLY_ON_PERIOD_END && safe_to_delay_apply)
            begin
                apply_pending   <=   1'b1;
            end

            //--------------------------------------------
            //Accepted MMIO transaction
            //--------------------------------------------
            if (req_fire)
			begin
                //Every request gets a response
                rsp_valid <= 1'b1;
                rsp_err   <= err_next;
                rsp_rdata <= rdata_next;

                //WRITE
                if (req_write)
				begin
                    if(duty_addr_hit)
                    begin
                        duty_shadow[duty_idx]   <=  merge_wstrb(
                            duty_shadow[duty_idx],
                            req_wdata,
                            req_wstrb);
                    end
                
                    else
                    begin
                        unique case (req_addr)

                            REG_CTRL:
                            begin
                                ctrl_shadow <= merge_wstrb(ctrl_shadow, req_wdata, req_wstrb);
                            end

                            REG_PERIOD:
                            begin
                                period_shadow <= merge_wstrb(period_shadow, req_wdata, req_wstrb);
                            end

                            REG_CH_ENABLE:
                            begin
                                ch_enable_shadow    <= merge_wstrb(
                                    {{(DATA_W-CHANNELS){1'b0}},ch_enable_shadow},
                                    req_wdata,
                                    req_wstrb)[CHANNELS-1:0];
                            end

                            REG_POLARITY:
                            begin
                                polarity_shadow <=  merge_wstrb(
                                    {{(DATA_W-CHANNELS){1'b0}}, polarity_shadow},
                                    req_wdata,
                                    req_wstrb)[CHANNELS-1:0];
                            end

                            REG_MOTOR_CTRL:
                            begin
                                motor_ctrl_shadow   <=  merge_wstrb(
                                    motor_ctrl_shadow,
                                    req_wdata,
                                    req_wstrb);
                            end

                            REG_APPLY:
                            begin
                                //No stored data; apply_pulse handles command semantics
                            end

                            default:
                            begin
                                rsp_err <= 1'b1;
                            end
                        endcase
                    end
                end
            end
        end
    end

    //---------------------------------
    //Outputs to core: active regs
    //---------------------------------
    assign  enable_o            =   ctrl_active[0]; //enable_active;
    assign  ch_enable_o         =   ch_enable_active;
    assign  period_cycles_o     =   period_active;
    assign  duty_cycles_o       =   duty_active;
    assign  polarity_o          =   polarity_active;
    assign  motor_ctrl_o        =   motor_ctrl_active;
endmodule