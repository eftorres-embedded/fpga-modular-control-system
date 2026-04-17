//i2c_reg.sv
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
module  i2c_regs    #(
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

//-------------------------------------------------------------
//Regsiter offsets
//-------------------------------------------------------------
localparam  logic   [ADDR_W-1:0]    REG_STATUS  =   'h000;
localparam  logic   [ADDR_W-1:0]    REG_DIVISOR =   'h004;
localparam  logic   [ADDR_W-1:0]    REG_TXDATA  =   'h008;
localparam  logic   [ADDR_W-1:0]    REG_RXDATA  =   'h00C;
localparam  logic   [ADDR_W-1:0]    REG_CMD     =   'h010;

//----------------------------------------------------------------
//Symbolic constant for CMDs
//----------------------------------------------------------------
localparam  logic   [CMD_W-1:0] START_CMD   =   'h0;
localparam  logic   [CMD_W-1:0] WR_CMD      =   'h1;
localparam  logic   [CMD_W-1:0] RD_CMD      =   'h2;
localparam  logic   [CMD_W-1:0] STOP_CMD    =   'h3;
localparam  logic   [CMD_W-1:0] RESTART_CMD =   'h4;

//----------------------------------------------------------------
//STATUS bits
//----------------------------------------------------------------
localparam  unsigned    int STATUS_CMD_READY        =   0;
localparam  unsigned    int STATUS_BUS_IDLE         =   1;
localparam  unsigned    int STATUS_DONE_TICK        =   2;
localparam  unsigned    int STATUS_ACK_VALID        =   3;
localparam  unsigned    int STATUS_ACK              =   4;
localparam  unsigned    int STATUS_RD_DATA_VALID    =   5;
localparam  unsigned    int STATUS_CMD_ILLEGAL      =   6;
localparam  unsigned    int STATUS_MASTER_RECEIVING =   7;


//--------------------------------------------------------------
//Helper function:  byte-write merge for 32-bit regs
//--------------------------------------------------------------
function    automatic   logic   [DATA_W-1:0]    merge_wstrb(
    input   logic   [DATA_W-1:0]        old_val,
    input   logic   [DATA_W-1:0]        new_val,
    input   logic   [(DATA_W/8)-1:0]    strb);

    logic   [DATA_W-1:0]    write_mask;
    begin
        write_mask  =   {
            {8{strb[3]}},
            {8{strb[2]}},
            {8{strb[1]}},
            {8{strb[0]}}
        };
        return  (old_val    &   ~write_mask)    |   (new_val    &   write_mask);
    end
endfunction


//-----------------------------------------------------------------
//Generic MMIO accpetance
//-----------------------------------------------------------------
assign  req_ready   =   !rsp_valid;

logic   req_fire;
logic   wr_fire;

assign  req_fire    =   req_valid   &&  req_ready;
assign  wr_fire     =   req_fire    &&  req_write;

//------------------------------------------------------------------
//Write decode helpers
//------------------------------------------------------------------
logic   wr_cmd_fire;
logic   wr_txdata_fire;
logic   wr_divisor_fire;

assign  wr_cmd_fire     =   wr_fire &&  (req_addr   ==  REG_CMD);
assign  wr_txdata_fire  =   wr_fire &&  (req_addr   ==  REG_TXDATA);
assign  wr_divisor_fire =   wr_fire &&  (req_addr   ==  REG_DIVISOR);

//--------------------------------------------------------------------
//Pulse commands generated from CMD Writes
//--------------------------------------------------------------------
logic   start_cmd_fire;
logic   write_tx_cmd_fire;
logic   read_cmd_fire;
logic   stop_cmd_fire;
logic   restart_cmd_fire;

assign  start_cmd_fire      =   wr_cmd_fire &&  req_wstrb[0]    &&  (req_wdata[CMD_W-1:0]   ==  START_CMD);
assign  write_tx_cmd_fire   =   wr_cmd_fire &&  req_wstrb[0]    &&  (req_wdata[CMD_W-1:0]   ==  WR_CMD);
assign  read_cmd_fire       =   wr_cmd_fire &&  req_wstrb[0]    &&  (req_wdata[CMD_W-1:0]   ==  RD_CMD);
assign  stop_cmd_fire       =   wr_cmd_fire &&  req_wstrb[0]    &&  (req_wdata[CMD_W-1:0]   ==  STOP_CMD);
assign  restart_cmd_fire    =   wr_cmd_fire &&  req_wstrb[0]    &&  (req_wdata[CMD_W-1:0]   ==  RESTART_CMD);