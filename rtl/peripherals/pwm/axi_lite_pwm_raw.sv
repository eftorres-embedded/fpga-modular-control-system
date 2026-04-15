// axi_lite_pwm_raw.sv
//
// AXI4-Lite wrapper for the V3 PWM subsystem.
//
// -----------------------------------------------------------------------------
// Design intent
// -----------------------------------------------------------------------------
// This wrapper translates an AXI4-Lite slave interface into the internal
// bus-agnostic MMIO request/response interface used by pwm_subsystem_raw.
//
// The wrapper keeps the same architectural style as the original version:
//   - single internal MMIO request channel
//   - single internal MMIO response channel
//   - reads and writes serialized through one Moore FSM
//   - decoupled AXI channels captured in holding registers
//
// -----------------------------------------------------------------------------
// Notes
// -----------------------------------------------------------------------------
// - 32-bit AXI data bus only
// - byte addresses are passed directly to pwm_subsystem_raw
// - reads and writes are serialized internally
// - write response uses OKAY / SLVERR from rsp_err
// - read response uses OKAY / SLVERR from rsp_err
//
// -----------------------------------------------------------------------------
// V3 register map note
// -----------------------------------------------------------------------------
// The actual register map is implemented inside pwm_regs_common.sv.
// The byte offsets visible through AXI-Lite are:
//
//   0x00  REG_CTRL
//   0x04  REG_PERIOD
//   0x08  REG_APPLY
//   0x0C  REG_CH_ENABLE
//   0x10  REG_STATUS
//   0x14  REG_CNT
//   0x20  REG_DUTY[0]
//   0x24  REG_DUTY[1]
//   0x28  REG_DUTY[2]
//   ...
//   0x20 + 4*i = REG_DUTY[i]

module  axi_lite_pwm_raw    #(
    parameter   int unsigned    AXI_ADDR_W              =   12,
    parameter   int unsigned    AXI_DATA_W              =   32,
    parameter   int unsigned    CNT_W                   =   32,
    parameter   int unsigned    CHANNELS                =   4,
    parameter   bit             APPLY_ON_PERIOD_END     =   1'b1)

    (
    input   logic                   clk,
    input   logic                   rst_n,
    
    //-------------------------------------------------------------
    //AXI4-Lite slave interface
    //-------------------------------------------------------------

    //Write address channel
    input   logic   [AXI_ADDR_W-1:0]            s_axil_awaddr,
    input   logic                               s_axil_awvalid,
    output  logic                               s_axil_awready,

    //Write data channel
    input   logic   [AXI_DATA_W-1:0]            s_axil_wdata,
    input   logic   [(AXI_DATA_W/8)-1:0]        s_axil_wstrb,
    input   logic                               s_axil_wvalid,
    output  logic                               s_axil_wready,

    //Write response channel
    output  logic   [1:0]                       s_axil_bresp,
    output  logic                               s_axil_bvalid,
    input   logic                               s_axil_bready,

    //Read Address channel
    input   logic   [AXI_ADDR_W-1:0]            s_axil_araddr,
    input   logic                               s_axil_arvalid,
    output  logic                               s_axil_arready,

    //Read data channel
    output  logic   [AXI_DATA_W-1:0]            s_axil_rdata,
    output  logic   [1:0]                       s_axil_rresp,
    output  logic                               s_axil_rvalid,
    input   logic                               s_axil_rready,


    //--------------------------------------------------------
    //PWM outputs / debug
    //--------------------------------------------------------
    output  logic   [CNT_W-1:0]                 cnt,
    output  logic                               period_end,
    output  logic   [CHANNELS-1:0]              pwm_o);

    //---------------------------------------------------------
    //AXI response encodings
    //AXI4-Lite uses a 2-bit response field on both the write-response
    //(BRESP) and the read-data channel (RRESP). 
    //We are only using :
    //OKAY = normal successful transaction
    //SLVERR = peripheral-reported error
    //---------------------------------------------------------
    localparam  logic   [1:0]   AXI_RESP_OKAY       =   2'b00;
    localparam  logic   [1:0]   AXI_RESP_SLVERR     =   2'b10;

    //---------------------------------------------------------
    //Internal generic MMIO interface to pwm_subsystem
    //---------------------------------------------------------
    logic                           req_valid;
    logic                           req_ready;
    logic                           req_write;
    logic   [AXI_ADDR_W-1:0]        req_addr;
    logic   [AXI_DATA_W-1:0]        req_wdata;
    logic   [(AXI_DATA_W/8)-1:0]    req_wstrb;

    logic                           rsp_valid;
    logic                           rsp_ready;
    logic   [AXI_DATA_W-1:0]        rsp_rdata;
    logic                           rsp_err;   

    //----------------------------------------------------------
    //State encoding
    //This Wrapper is intentionally implemented as a single Moore FSM:
    //
    // - outputs are driven from the current state
    // - payloads are held in registers
    // - reads and writes are serialized
    //
    // States:
    // 
    //IDLE: No transaction in progress.
    //
    //WR_WAIT_DATA: Write address has been accepted, but write data
    //has not yet been accepted
    //
    //WR_WAIT_ADDR: Write data has been accepted, but write address
    //has not yet been accepted.
    //
    //WR_ISSUE: Drive a write request into pwm_subsystem
    //
    //WR_WAIT_RSP: Wait for pwm_subsystem to produce a write response
    //
    //WR_SEND_B: Present AXI write response to the master
    //
    //RD_ISSUE: Drive a read request into pwm_subsystem
    //
    //RD_WAIT_RSP: Wait for pwm_subsystem to produce read data/response
    //
    //RD_SEND_R: Present AXI read data/response to the master.
    //------------------------------------------------------------
    typedef enum logic  [3:0]
    {
        IDLE,
        WR_WAIT_DATA,
        WR_WAIT_ADDR,
        WR_ISSUE,
        WR_WAIT_RSP,
        WR_SEND_B,
        RD_ISSUE,
        RD_WAIT_RSP,
        RD_SEND_R
    }   state_t;

    state_t current_state, next_state;

    //----------------------------------------------------------
    //AXI payload holding register
    //Because AXI channels are decoupled, address and data may arrive on different cycles.
    //
    //So they are held until the internal MMIO request can be issued.
    //----------------------------------------------------------
    logic   [AXI_ADDR_W-1:0]        awaddr_reg;
    logic   [AXI_DATA_W-1:0]        wdata_reg;
    logic   [(AXI_DATA_W/8)-1:0]    wstrb_reg;

    logic   [AXI_ADDR_W-1:0]        araddr_reg;

    //----------------------------------------------------------
    //AXI response holding registers
    //
    //These registers store the response returned by pwm_subsystem so it can
    //be presented cleanly on AXI side during the response states.
    //-----------------------------------------------------------
    logic   [1:0]                   bresp_reg;
    logic   [AXI_DATA_W-1:0]        rdata_reg;
    logic   [1:0]                   rresp_reg;

    //-----------------------------------------------------------
    //Local handshake helpers
    //Signals to indicate if a handsahke happened on this cycle.
    //Handshake occurs only when VALID and READY are both high in 
    //the same cycle
    //-----------------------------------------------------------
    logic aw_fire, w_fire, ar_fire, b_fire, r_fire;

    assign  aw_fire =   s_axil_awvalid  &&  s_axil_awready;
    assign  w_fire  =   s_axil_wvalid   &&  s_axil_wready;
    assign  ar_fire =   s_axil_arvalid  &&  s_axil_arready;
    assign  b_fire  =   s_axil_bvalid   &&  s_axil_bready;
    assign  r_fire  =   s_axil_rvalid   &&  s_axil_rready;

    logic   req_fire,   rsp_fire;
    assign  req_fire    =   req_valid   &&  req_ready;
    assign  rsp_fire    =   rsp_valid   &&  rsp_ready;

    

    //----------------------------------------------------------
    //Instatiate PWM subsystem
    //
    //The AXI wrapper's job is to translate the bus protocol
    //into the req/rsp MMIO interface
    //----------------------------------------------------------
    pwm_subsystem_raw #(
        .ADDR_W(AXI_ADDR_W),
        .DATA_W(AXI_DATA_W),
        .CNT_W(CNT_W),
        .CHANNELS(CHANNELS),
        .APPLY_ON_PERIOD_END(APPLY_ON_PERIOD_END))
        
        u_pwm_subsystem (
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

        .cnt(cnt),
        .period_end(period_end),
        .pwm_o(pwm_o));  

        
    //--------------------------------------------------------------
    //State register
    //--------------------------------------------------------------
    always_ff   @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
            current_state   <=  IDLE;
        else
            current_state   <=  next_state;
    end


    //----------------------------------------------------------------
    //Sequential storage for captured AXI payloads and captured
    //subsystem responses
    //
    //This block is responsible only for storage,
    //it does not decide state transitions
    //----------------------------------------------------------------
    always_ff   @(posedge   clk or  negedge rst_n)
    begin
        if(!rst_n)
        begin
            awaddr_reg  <=  '0;
            wdata_reg   <=  '0;
            wstrb_reg   <=  '0;
            araddr_reg  <=  '0;

            bresp_reg   <=  AXI_RESP_OKAY;
            rdata_reg   <=  '0;
            rresp_reg   <=  AXI_RESP_OKAY;
        end

        else
        begin
            //--------------------------------------------------------
            //Capture write address when AW handshakes
            //--------------------------------------------------------
            if(aw_fire)
            begin
                awaddr_reg  <=  s_axil_awaddr;
            end

            //--------------------------------------------------------
            //Capture write data and byte strobes when W handshakes
            //--------------------------------------------------------
            if(w_fire)
            begin
                wdata_reg   <=  s_axil_wdata;
                wstrb_reg   <=  s_axil_wstrb;
            end

            //---------------------------------------------------------
            //Capture read address when AR hanshakes
            //---------------------------------------------------------
            if(ar_fire)
            begin
                araddr_reg  <=  s_axil_araddr;
            end

            //----------------------------------------------------------
            //Capture write response returned by the subsystem while 
            //waiting for it
            //---------------------------------------------------------
            if((current_state   ==  WR_WAIT_RSP) && rsp_fire)
            begin
                bresp_reg   <=  rsp_err ?   AXI_RESP_SLVERR :   AXI_RESP_OKAY;
            end

            //-----------------------------------------------------------
            //Capture read data/response returned by the subsystem while
            //waiting for it
            //-----------------------------------------------------------
            if((current_state   ==  RD_WAIT_RSP)    &&  rsp_fire)
            begin
                rdata_reg   <=  rsp_rdata;
                rresp_reg   <=  rsp_err ?   AXI_RESP_SLVERR :   AXI_RESP_OKAY;
            end
        end
    end

    //-----------------------------------------------------------------------
    //Next-state logic
    //
    //This block decides where teh FSM goes next based on the current state and
    //current handsakes.
    //
    //Priority policy in IDLE:
    //  1st - Complete write (AW and W same cycle)
    //  2nd - partial write address
    //  3rd - partial write data
    //  4th - read address
    //-------------------------------------------------------------------------
    always_comb
    begin
        next_state  =   current_state;

        unique  case    (current_state)
            //---------------------------------------------------------------------
            //IDLE:
            //Ready to accept a new request
            //
            //Four possibilities:
            //  - AW and W arrive together  ->  Full write (both address and data)
            //  - only AW arrives           ->  wait for W
            //  - only W  arrives           ->  wait for AW
            //  - AR arrives                ->  issue read
            //---------------------------------------------------------------------
            IDLE:
            begin
                if(aw_fire  && w_fire)
                    next_state  =   WR_ISSUE;
                else if(aw_fire)
                    next_state  =   WR_WAIT_DATA;
                else if(w_fire)
                    next_state  =   WR_WAIT_ADDR;
                else if(ar_fire)
                    next_state  =   RD_ISSUE;
            end

            //---------------------------------------------------------------------
            //Have write address, waiting for write data
            //---------------------------------------------------------------------
            WR_WAIT_DATA:
            begin
                if(w_fire)
                    next_state  =   WR_ISSUE;
            end

            //---------------------------------------------------------------------
            //Have write data,  waiting for write address
            //---------------------------------------------------------------------
            WR_WAIT_ADDR:
            begin
                if(aw_fire)
                    next_state  =   WR_ISSUE;
            end

            //---------------------------------------------------------------------
            //Present internal write request, continue once the subsystem accepts it
            //---------------------------------------------------------------------
            WR_ISSUE:
            begin
                if(req_fire)
                    next_state  =   WR_WAIT_RSP;
            end

            //---------------------------------------------------------------------
            //Wait for subsystem write response
            //---------------------------------------------------------------------
            WR_WAIT_RSP:
            begin
                if(rsp_fire)
                    next_state  =   WR_SEND_B;
            end

            //---------------------------------------------------------------------
            //Hold AXI write response until master accepts it
            //---------------------------------------------------------------------
            WR_SEND_B:
            begin
                if(b_fire)
                    next_state  =   IDLE;
            end

            //---------------------------------------------------------------------
            //Present internal read request and continue once the pwm subsystem
            //accepts it
            //---------------------------------------------------------------------
            RD_ISSUE:
            begin
                if(req_fire)
                    next_state  =   RD_WAIT_RSP;
            end

            //---------------------------------------------------------------------
            //Wait for PWM subsystem read data/response
            //---------------------------------------------------------------------
            RD_WAIT_RSP:
            begin
                if(rsp_fire)
                    next_state  =   RD_SEND_R;
            end

            //---------------------------------------------------------------------
            //Hold AXI read data/response until master accepts it
            //---------------------------------------------------------------------
            RD_SEND_R:
            begin
                if(r_fire)
                    next_state  =   IDLE;
            end

            default:
            begin
                next_state  =   IDLE;
            end
        endcase
    end


    //------------------------------------------------------------------------------
    //All bus output and internal req/rsp control signals are driven from state 
    //and holding registers.
    //
    //This block contains no storage.
    //------------------------------------------------------------------------------
    always_comb
    begin
        
        //Default AXI outputs
        s_axil_awready  =   1'b0;
        s_axil_wready   =   1'b0;
        s_axil_arready  =   1'b0;

        s_axil_bvalid   =   1'b0;
        s_axil_bresp    =   bresp_reg;

        s_axil_rvalid   =   1'b0;
        s_axil_rdata    =   rdata_reg;
        s_axil_rresp    =   rresp_reg;

        //Default internal MMIO request/response
        req_valid       =   1'b0;
        req_write       =   1'b0;
        req_addr        =   '0;
        req_wdata       =   '0;
        req_wstrb       =   '0;

        rsp_ready       =   1'b0;

        unique case (current_state)

            //----------------------------------------------------------------------
            //IDLE:
            //Accept new traffic on all request-entry channels. Atransaction is chosen 
            //by the next-state logic according to priority
            //----------------------------------------------------------------------
            IDLE: 
            begin
                s_axil_awready  =   1'b1;
                s_axil_wready   =   1'b1;
                s_axil_arready  =   1'b1;
            end

            //-----------------------------------------------------------------------
            //Only waiting for write data now
            //-----------------------------------------------------------------------
            WR_WAIT_DATA:
            begin
                s_axil_wready   =   1'b1;
            end

            //-----------------------------------------------------------------------
            //Only waiting for write address now
            //-----------------------------------------------------------------------
            WR_WAIT_ADDR:
            begin
                s_axil_awready  =   1'b1;
            end

            //-----------------------------------------------------------------------
            //Drive internal write request using the previously captured AW/W payloads
            //-----------------------------------------------------------------------
            WR_ISSUE:
            begin
                req_valid   =   1'b1;
                req_write   =   1'b1;
                req_addr    =   awaddr_reg;
                req_wdata   =   wdata_reg;
                req_wstrb   =   wstrb_reg;
            end

            //-----------------------------------------------------------------------
            //Tell pwm subsystem we are ready to receive its response
            //-----------------------------------------------------------------------
            WR_WAIT_RSP:
            begin
                rsp_ready   =   1'b1;
            end

            //-----------------------------------------------------------------------
            //Hold write response on AXI until master accepts it
            //-----------------------------------------------------------------------
            WR_SEND_B:
            begin
                s_axil_bvalid   =   1'b1;
                s_axil_bresp    =   bresp_reg;
            end

            //-----------------------------------------------------------------------
            //Drive internal read request using the previously capture AR payload
            //-----------------------------------------------------------------------
            RD_ISSUE:
            begin
                req_valid   =   1'b1;
                req_write   =   1'b0;
                req_addr    =   araddr_reg;
            end

            //-----------------------------------------------------------------------
            //Tell pwm subsystem we are ready to receive the read data/response
            //-----------------------------------------------------------------------
            RD_WAIT_RSP:
            begin
                rsp_ready   =   1'b1;
            end

            //-----------------------------------------------------------------------
            //Hold read data/response on AXI until master accpets it
            //-----------------------------------------------------------------------
            RD_SEND_R:
            begin
                s_axil_rvalid   =   1'b1;
                s_axil_rdata    =   rdata_reg;
                s_axil_rresp    =   rresp_reg;
            end

            default:
            begin
                //keep defaults
            end
        endcase
    end
endmodule