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


endmodule