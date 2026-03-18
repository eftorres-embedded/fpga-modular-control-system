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
    //AXI channel holding registers
    //----------------------------------------------------------
    logic                           aw_hold_valid;
    logic   [AXI_ADDR_W-1:0]        aw_hold_addr;

    logic                           w_hold_valid;
    logic   [AXI_DATA_W-1:0]        w_hold_data;
    logic   [AXI_DATA_W/8)-1:0]     w_hold_strb;
    
    logic                           ar_hold_valid;
    logic   [AXI_ADDR_W-1:0]        ar_hold_addr;

    //----------------------------------------------------------
    //Internal transaction tracking
    //----------------------------------------------------------
    logic                           wr_req_inflight;
    logic                           rd_req_inflight;

    logic                           issue_write_req;
    logic                           issue_read_req;

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

        //-----------------------------------------------------------
        //AXI ready generation
        //
        //Only accept:
        // - AW when no stored AW and no write request/response in progress 



endmodule