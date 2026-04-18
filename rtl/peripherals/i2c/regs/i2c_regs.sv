//core_reg.sv
//---------------------------------------------------------------------------
//Register map
//
//0x00 REG_STATUS   (R)
//     [0] cmd_ready
//     [1] bus_idle
//     [2] done_tick
//     [3] ack_valid
//     [4] ack
//     [5] rd_data_valid
//     [6] cmd_illegal
//     [7] master_receiving
//
//0x04 REG_DIVISOR  (R/W)
//     [DIVISOR_W-1:0] divisor
//
//0x08 REG_TXDATA   (R/W)
//     [7:0] tx byte staging register
//
//0x0C REG_RXDATA   (R)
//     [7:0] last captured RX byte
//
//0x10 REG_CMD      (W)
//     [2:0] cmd
//     [8]   rd_last
//
//Philosophy:
//- V1 is polling-first, so status is live rather than sticky.
//- REG_CMD is an action register, not retained state.
//- No internal command queue: software must only launch when cmd_ready=1.
//---------------------------------------------------------------------------
module  core_regs    #(
    parameter   int ADDR_W  =   12,
    parameter   int DATA_W  =   32,
    parameter   int BYTE_W  =   8,
    parameter   int CMD_W   =   3,
    parameter   int DIVISOR =   16)
    (
    input   logic               clk,
    input   logic               rst_n,

    //Generic   project MMIO request channel
    input   logic                   req_valid,
    output  logic                   req_ready,
    input   logic                   req_write,
    input   logic   [ADDR_W-1:0]    req_addr,
    input   logic   [DATA_W-1:0]    req_wdata,
    input   logic   [(DATA/8)-1:0]  req_wstrb,

    //Generic project MMIO response channel
    output  logic                   rsp_valid,
    input   logic                   rsp_ready,
    output  logic   [DATA_W-1:0]    rsp_rdata,
    output  logic                   rsp_err,

    //-----------------------------------------------------------
    //external I2C pin / pin-control
    //-----------------------------------------------------------
    input   logic                   sda_in,
    output  logic                   sda_out,
    input   logic                   scl_in,
    output  logic                   scl_out,
    output  logic                   master_receiving_o);

//--------------------------------------------------------------
//I2C core status/interface_signals
//--------------------------------------------------------------
logic   [BYTE_W-1:0]    i2c_rx_data;
logic                   i2c_cmd_ready;
logic                   i2c_cmd_illegal;
logic                   i2_done_tick;
logic                   i2c_ack;
logic                   i2c_ack_valid;
logic                   i2c_rd_data_valid;
logic                   i2c_bus_idle;
logic                   i2c_master_receiving;

//--------------------------------------------------------------
//stored software-visible registers
//---------------------------------------------------------------
logic   [BYTE_W-1:0]    txdata_reg;
logic   [BYTE_W-1:0]    rxdtat_reg;
logic   [DIVISOR_W-1:0] divisor_reg;

//--------------------------------------------------------------
//Generic MMIO acceptance
//--------------------------------------------------------------
logic   req_fire;
logic   wr_fire;
logic   rsp_fire;

assign  rsp_fire    =   rsp_valid       &&  rsp_ready;
assign  req_ready   =   (!rsp_valid)    ||  rsp_fire;
assign  req_fire    =   req_valid       &&  req_ready;
assign  wr_fire     =   req_fire        &&  req_write;

//---------------------------------------------------------------
//Write decode helpers
//---------------------------------------------------------------
logic   wr_cmd_fire;
logic   wr_txdata_fire;
logic   wr_divisor_fire;

assign  wr_cmd_fire     =   wr_fire &&  (req_addr   ==  REG_CMD);
assign  wr_txdata_fire  =   wr_fire &&  (req_addr   ==  REG_TXDATA);
assign  wr_divisor_fire =   wr_fire &&  (req_addr   ==  REG_DIVISOR);

//----------------------------------------------------------------
//Temporary merged values and command launch payload
//---------------------------------------------------------------
logic   [DATA_W-1:0]    status_rdata;
logic   [DATA_W-1:0]    txdata_merged;
logic   [DATA_W-1:0]    divisor_merged;
logic   [DATA_W-1:0]    cmd_merged;

logic   [CMD_W-1:0]     launch_cmd;
logic                   launch_rd_last;
logic                   launch_cmd_fire;

assign  txdata_merged   =   merge_wstrb({{(DATA_W-BYTE_W){1'b0}},   txdata_reg}, req_wdata, req_wstrb);
assign  divisor_merged  =   merge_wstrb({{(DATA_W-DIVISOR_W){1'b0}},    divisor_reg},   req_wdta,   req_wstrb);

//REG_CMD is action-oriented, the whole command needs to be written not merged or masked
//Byte 0 must be present for a valid launch because cmd livs in bits [2:0]