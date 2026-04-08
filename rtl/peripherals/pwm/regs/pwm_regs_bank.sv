//pwm_core_bank.sv
//this is just a temporary file it will be use as a scratch pad before commiting to the oriignal pwm_core_ip.sv file//pwm_regs.sv
//
// Generic MMIO register file for PWM core.
//
// Features:
// - Bus-agnostic MMIO (req_valid/req_ready, rsp_valid/rsp_ready)
// - Shadow registers for CTRL / PERIOD / DUTY
// - Separate APPLY register (write 1 to request commit)
// - Optional boundary-synchronous commit to period_end_i
// - Startup-safe APPLY behavior: if PWM is not yet in a valid active-running
//   state, APPLY commits immediately even when APPLY_ON_PERIOD_END = 1
//
// Software contract:
// 1. Write REG_CTRL bits [1:0] if needed
// 2. Write REG_PERIOD
// 3. Write REG_DUTY
// 4. Write REG_APPLY bit[0] = 1
//
// Notes:
// - REG_CTRL reads back SHADOW control bits (what software configured)
// - REG_STATUS exposes ACTIVE control bits
// - REG_APPLY is command-style; reads return 0
//

module pwm_regs #(
    parameter   int unsigned    ADDR_W  =   12,
    parameter   int unsigned    DATA_W  =   32,
    parameter   int unsigned    CNT_W   =   32,

    // If 1: APPLY waits until period_end_i before updating active regs,
    // unless startup/inactive bypass is needed.
    // If 0: APPLY updates active regs immediately.
    parameter   bit APPLY_ON_PERIOD_END =   1'b1)
(
    input   logic                       clk,
    input   logic                       rst_n,

    //--------------------------------------
    // Generic MMIO request channel
    //--------------------------------------
    input   logic                       req_valid,
    output  logic                       req_ready,
    input   logic                       req_write,      // 1=write, 0=read
    input   logic   [ADDR_W-1:0]        req_addr,       // byte address
    input   logic   [DATA_W-1:0]        req_wdata,
    input   logic   [(DATA_W/8)-1:0]    req_wstrb,

    //---------------------------------------
    // Generic MMIO response channel
    //---------------------------------------
    output  logic                       rsp_valid,
    input   logic                       rsp_ready,
    output  logic   [DATA_W-1:0]        rsp_rdata,
    output  logic                       rsp_err,        // 1 = decode error

    //---------------------------------------
    // Interface signals to/from PWM core
    //---------------------------------------
    input   logic                       period_end_i,   // one-cycle pulse from core
    input   logic   [CNT_W-1:0]         cnt_i,          // live counter from core

    output  logic                       enable_o,
    output  logic                       use_default_duty_o,
    output  logic   [CNT_W-1:0]         period_cycles_o,
    output  logic   [CNT_W-1:0]         duty_cycles_o);

    //------------------------------------------------
    // Register offsets (byte)
    //------------------------------------------------
    localparam  logic   [ADDR_W-1:0]    REG_CTRL    = 'h00;
    localparam  logic   [ADDR_W-1:0]    REG_PERIOD  = 'h04;
    localparam  logic   [ADDR_W-1:0]    REG_DUTY    = 'h08;
    localparam  logic   [ADDR_W-1:0]    REG_APPLY   = 'h0C;
    localparam  logic   [ADDR_W-1:0]    REG_STATUS  = 'h10;
    localparam  logic   [ADDR_W-1:0]    REG_CNT     = 'h14;

    //------------------------------------------------
    // Internal state: shadow + active
    //------------------------------------------------

	logic   [DATA_W-1:0]     ctrl_shadow;
    logic   [CNT_W-1:0]     period_shadow;
    logic   [CNT_W-1:0]     duty_shadow;

	logic   [DATA_W-1:0]    ctrl_active;
    logic   [CNT_W-1:0]     period_active;
    logic   [CNT_W-1:0]     duty_active;

    //------------------------------------------------
    // APPLY handling
    //------------------------------------------------
    logic                   apply_pulse;         // one-cycle pulse when SW writes REG_APPLY[0]=1
    logic                   apply_pending;       // pending deferred commit
    logic                   safe_to_delay_apply; // active PWM already running
    logic                   apply_commit_now;    // commit shadow -> active this cycle

    //------------------------------------------------
    // Response buffering
    //------------------------------------------------
    logic                   accept_req;
    logic   [DATA_W-1:0]    rdata_next;
    logic                   err_next;

    //-------------------------------------------------
    // Ready/valid: single outstanding response
    //-------------------------------------------------
    assign  req_ready   =   (!rsp_valid) || (rsp_valid && rsp_ready);
    assign  accept_req  =   req_valid && req_ready;

    //-------------------------------------------------
    // Helper function: byte-write merge for 32-bit regs
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

    //--------------------------------------------------
    // Read mux
    //--------------------------------------------------
    always_comb 
	 begin
        rdata_next = '0;
        err_next   = 1'b0;

        unique case (req_addr)

            REG_CTRL:
			begin
                // Read back SHADOW control bits like a normal RW register
                rdata_next = ctrl_shadow; //enable_shadow;
                
            end

            REG_PERIOD:
			begin
                rdata_next = period_shadow;
            end

            REG_DUTY:
			begin
                rdata_next = duty_shadow;
            end

            REG_APPLY:
			begin
                // Command register: read as 0
                rdata_next = '0;
            end

            REG_STATUS:
			begin
                rdata_next[0] = period_end_i;
                rdata_next[1] = apply_pending;
                rdata_next[2] = ctrl_active[0]; //enable
                rdata_next[3] = ctrl_active[1];	//default period
            end

            REG_CNT:
			begin
                rdata_next = cnt_i;
            end

            default:
			begin
                rdata_next = '0;
                err_next   = 1'b1;
            end
        endcase
    end

    //-------------------------------------------------
    // APPLY pulse detection
    // REG_APPLY bit[0] is write-one-to-apply
    //-------------------------------------------------
    always_comb
	begin
        apply_pulse = 1'b0;

        if(accept_req && req_write && (req_addr == REG_APPLY))
		begin
            if(req_wstrb[0] && req_wdata[0])
                apply_pulse = 1'b1;
        end
    end

    //---------------------------------------------------
    // Deferred/immediate APPLY control
    //---------------------------------------------------
    always_comb
	begin
        // Defer only when PWM is already active and has a valid active period.
        // This avoids startup deadlock when APPLY_ON_PERIOD_END=1.
        safe_to_delay_apply = ctrl_active[0] && (period_active != '0);

        apply_commit_now = 1'b0;

        if(APPLY_ON_PERIOD_END)
		begin
            if(apply_pulse || apply_pending)
			begin
                if(!safe_to_delay_apply)
                    apply_commit_now = 1'b1;   // startup/inactive bypass
                else if(period_end_i)
                    apply_commit_now = 1'b1;   // normal synchronized commit
            end
        end
		  
        else
		begin
            apply_commit_now = apply_pulse;    // immediate mode
        end
    end

    always_ff @(posedge clk or negedge rst_n)
	begin
        if(!rst_n)
		begin
            ctrl_shadow		<= '0;
            period_shadow	<= '0;
            duty_shadow		<= '0;

            // Active regs
            ctrl_active		<= '0;
            period_active	<= '0;
            duty_active		<= '0;

            apply_pending	<= 1'b0;

            rsp_valid		<= 1'b0;
            rsp_rdata		<= '0;
            rsp_err			<= 1'b0;
        end
		  
        else
		begin
            //--------------------------------------------
            // Response channel clear
            //--------------------------------------------
            if (rsp_valid && rsp_ready)
                rsp_valid <= 1'b0;

            //--------------------------------------------
            // APPLY commit path
            //--------------------------------------------
            if(apply_commit_now)
			begin
                ctrl_active		<= ctrl_shadow;
                period_active	<= period_shadow;
                duty_active		<= duty_shadow;
                apply_pending	<= 1'b0;
            end
				
            else if(APPLY_ON_PERIOD_END && apply_pulse)
			begin
                apply_pending       <= 1'b1;
            end
				
            else if(!APPLY_ON_PERIOD_END)
			begin
                apply_pending       <= 1'b0;
            end

            //--------------------------------------------
            // Accepted MMIO transaction
            //--------------------------------------------
            if (accept_req)
			begin
                // Every request gets a response
                rsp_valid <= 1'b1;
                rsp_err   <= 1'b0;
                rsp_rdata <= '0;

                // READ
                if (!req_write)
				begin
                    rsp_rdata <= rdata_next;
                    rsp_err   <= err_next;
                end

                // WRITE
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

                        REG_DUTY:
						begin
                            duty_shadow   <= merge_wstrb(duty_shadow, req_wdata, req_wstrb);
                        end

                        REG_APPLY:
						begin
                            // No stored data; apply_pulse handles command semantics
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

    //---------------------------------
    // Outputs to core: active regs
    //---------------------------------
    assign enable_o            = ctrl_active[0]; //enable_active;
    assign use_default_duty_o  = ctrl_active[1]; //use_default_active;
    assign period_cycles_o     = period_active;
    assign duty_cycles_o       = duty_active;

endmodule