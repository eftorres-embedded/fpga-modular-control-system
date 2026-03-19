//axi_lit_pwm.sv
//
// AXI-Lite wrappper for PWM subsystem.
//
//Notes: 
// - 32-bit data only
// - Byte addresses are passed through directly to pwm_subsystem
// - Single internal MMIO request/response channel is shared between reads and writes
// - Reads and writes are serialized internally 
// - AXI Write response uses OKAY/SLVERR based on rsp_err
// - AXI read response uses OKAY/SLVERR based on rsp_err
//
//Register map (byte offsets):
//  0x00    :   CTRL
//  0x04    :   PERIOD
//  0x08    :   DUTY
//  0x0C    :   STATUS
//  0x10    :   CNT

module  axi_lite_pwm    #(
    parameter   int unsigned    AXI_ADDR_W              =   12,
    parameter   int unsigned    AXI_DATA_W              =   32,
    parameter   int unsigned    CNT_W                   =   32,
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

    //Read address channel
    input   logic   [AXI_ADDR_W-1:0]            s_axil_araddr,
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
    input   logic   [AXI_ADDR_W-1:0]            s_axil_rdata,
    input   logic                               s_axil_arvaild,
    output  logic                               s_axil_arready,

    //Read data channel
    output  logic   [AXI_DATA_W-1:0]            s_axil_rdata,
    output  logic   [1:0]                       a_axil_rresp,
    output  logic                               s_axil_rvalid,
    input   logic                               s_axil_rready,

    //--------------------------------------------------------
    //PWM outputs / debug
    //--------------------------------------------------------
    output  logic   [CNT_W-1:0]                 cnt,
    output  logic                               period_end,
    output  logic                               pwm_raw);

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
    //WR_WAIT_DATA: Write data has been accepted, but write address
    //has not yet been accepted.
    //
    //WR_ISSUE: Drive a write request into pwm_subsystem
    //
    //WR_WAIT_RSP: Wait for pwm_subsystem to produce a wirte response
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
    assign  r_fire  =   s_axili_rvalid  &&  s_axil_rreday;

    

    //----------------------------------------------------------
    //Instatiate PWM subsystem
    //----------------------------------------------------------
    pwm_subsystem #(
        .ADDR_W(AXI_ADDR_W),
        .DATA_W(AXI_DATA_W),
        .CNT_W(CNT_W),
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
        .pwm_raw(pwm_raw));  

        



endmodule