//pwm_regs.sv
//
//Generic MMIO register file for PWM core.
//
//Features:
//-Bus-agnostic MMIO (req_valid/req_ready, rsp_valid/rsp_ready)
//-Shadow register for period/duty
//-APPLY bit (write 1) copies shadow register to active registers and auto-clears in hardware
//boundary-sync of APPLY to period_end as a parameter
//For now, only 32-bit MMIO, CNT_W and DATA_W should be 32-bit
//////////////////////////////////////////////////////////////////////////////
//For hardware simplification there will be a Software contract:
//1. Write `REG_PERIOD`
//2. Write `REG_DUTY`
//3. Write `REG_CTRL` bits `[1:0]` if needed
//4. Write `REG_CTRL` with only `APPLY` bit set (bit 2)
//////////////////////////////////////////////////////////////////////////////

module pwm_regs #(
    parameter int unsigned ADDR_W   =   12, //enough for offsets
    parameter int unsigned DATA_W   =   32,
    parameter int unsigned CNT_W    =   32,

    //If 1: APPLY waits until period_end_i before updating active regs.
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
    input   logic                       period_end_i,   //from core (one-cycle pulse)
    input   logic   [CNT_W-1:0]         cnt_i,           //from core

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
    logic               apply_pulse;    //one-cycle internal strobe when SW writes apply=1
    logic               apply_pending;   //if boundary sync enabled

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

        logic [DATA_W-1:0]    write_mask;
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
                rdata_next[1]   =   use_default_active;
                rdata_next[2]   =   1'b0;               //APPLY always reads as 0
            end

            REG_PERIOD: begin
                rdata_next  =   period_shadow;          //Software writes back what it wrote, even if APPLY has not happened yet
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
                err_next    =   1'b1;   //decode error, wrong address
            end
        endcase
    end

    //-------------------------------------------------
    //APPLY pulse detection (from CTRL writes)
    //APPLY is write-one. It clears automatically
    //-------------------------------------------------
    always_comb
    begin
        apply_pulse =   1'b0;
        if(accept_req && req_write && (req_addr ==  REG_CTRL))  //only accepted writes to CTRL reg
        begin
            //If byte lane containing bit[2] (byte 0 - req_wstrb[0])
            if(req_wstrb[0] && req_wdata[2])    //making sure that software wants to write to bit-2 of byte 0
                apply_pulse =   1'b1;
        end
    end


    //----------------------------------------------------
    //Register Writes, APPLY behavior, response buffering
    //----------------------------------------------------
    logic   [DATA_W-1:0]    ctrl_merged;
    always_comb
    begin
        ctrl_merged  =   merge_wstrb( 
                {{(DATA_W-2){1'b0}}, use_default_shadow, enable_shadow},
                req_wdata,
                req_wstrb);
    end

    always_ff @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            //shadows default to 0 and actives default to safe known values
            enable_shadow       <=  1'b0;
            use_default_shadow  <=  1'b0;
            period_shadow       <=  '0;
            duty_shadow         <=  '0;

            enable_active       <=  1'b0;
            use_default_active  <=  1'b0;
            period_active       <=  '0;
            duty_active         <=  '0;

            apply_pending       <=  1'b0;

            rsp_valid           <=  1'b0;
            rsp_rdata           <=  '0;
            rsp_err             <=  1'b0;
        end

        else
        begin
            //Clear response once accepted by master
            if(rsp_valid && rsp_ready)
                rsp_valid   <=  1'b0;
            
            //Default: if boundary-sync is enabled, APPLY is pending until period_end_i
            //For hardware simplification there will be a Software contract:
            //1. Write `REG_PERIOD`
            //2. Write `REG_DUTY`
            //3. Write `REG_CTRL` bits `[1:0]` if needed
            //4. Write `REG_CTRL` with only `APPLY` bit set (bit 2)
            if(APPLY_ON_PERIOD_END)
            begin
                //if APPLY pulse is set and the same time as period_end_i,
                //the active registers will be updated
                if((apply_pending || apply_pulse )  &&  period_end_i)
                begin
                    enable_active       <=  enable_shadow;
                    use_default_active  <=  use_default_shadow;
                    period_active       <=  period_shadow;
                    duty_active         <=  duty_shadow;
                    apply_pending       <=  1'b0;           //auto-clear
                end

                else if(apply_pulse)
                begin
                    apply_pending   <=  1'b1;
                end
                
            end

            else
            begin
                //immediate apply
                if(apply_pulse)
                begin
                    enable_active       <=  enable_shadow;
                    use_default_active  <=  use_default_shadow;
                    period_active       <=  period_shadow;
                    duty_active         <=  duty_shadow;
                    //apply auto-clears by virtue of not storing it
                end
                apply_pending   <=  1'b0;
            end


            //Handle accepted transaction
            if(accept_req)
            begin
                //Produce a response for every request (read returns data, write returns 0)
                rsp_valid   <=  1'b1;
                rsp_err     <=  1'b0;
                rsp_rdata   <=  '0;

                //READ
                if(!req_write)
                begin
                    rsp_rdata   <=  rdata_next;
                    rsp_err     <=  err_next;
                end

                //WRITE
                else
                begin
                    unique case(req_addr)
                        REG_CTRL:   begin
                            //Merge using wstrb (CTRL is in bits [1:0], apply is W1 (write-1) in bit[2])
                            //Writes update SHADOW ctrl bits    (not active).
                            //APPLY bit is not handled here, it was done via apply_pulse
                            enable_shadow       <=  ctrl_merged[0];
                            use_default_shadow  <=  ctrl_merged[1];

                        end

                        REG_PERIOD: begin
                            period_shadow   <=  merge_wstrb(period_shadow, req_wdata, req_wstrb); 
                        end

                        REG_DUTY:   begin
                            duty_shadow     <=  merge_wstrb(duty_shadow, req_wdata, req_wstrb);
                        end

                        default:    begin
                            //writing to invalid offset
                            rsp_err <=  1'b1;
                        end
                    endcase
                end
            end
        end
    end

    //---------------------------------
    //Outputs to core: Active regs
    //---------------------------------
    assign  enable_o            =   enable_active;
    assign  use_default_duty_o  =   use_default_active;
    assign  period_cycles_o     =   period_active;
    assign  duty_cycles_o       =   duty_active;

endmodule