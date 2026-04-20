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
    parameter   int                     ADDR_W      =   12,
    parameter   int                     DATA_W      =   32,
    parameter   int                     BYTE_W      =   8,
    parameter   int                     CMD_W       =   3,
    parameter   int                     DIVISOR_W   =   16,
    parameter   logic   [DIVISOR_W-1:0] MIN_DIVISOR =   'd1)
    (
    input   logic               clk,
    input   logic               rst_n,

    //Generic   project MMIO request channel
    input   logic                       req_valid,
    output  logic                       req_ready,
    input   logic                       req_write,
    input   logic   [ADDR_W-1:0]        req_addr,
    input   logic   [DATA_W-1:0]        req_wdata,
    input   logic   [(DATA_W/8)-1:0]    req_wstrb,

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

// -------------------------------------------------------------
// Register map
//
// 0x00 REG_STATUS   (R)
//      [0] cmd_ready
//      [1] bus_idle
//      [2] done_tick
//      [3] ack_valid
//      [4] ack
//      [5] rd_data_valid
//      [6] cmd_illegal
//      [7] master_receiving
//
// 0x04 REG_DIVISOR  (R/W)
//      [DIVISOR_W-1:0] divisor
//
// 0x08 REG_TXDATA   (R/W)
//      [7:0] tx byte staging register
//
// 0x0C REG_RXDATA   (R)
//      [7:0] last captured RX byte
//
// 0x10 REG_CMD      (W)
//      [2:0] cmd
//      [8]   rd_last
//--------------------------------------------------------------
localparam  logic   [ADDR_W-1:0]    REG_STATUS  =   12'h000;
localparam  logic   [ADDR_W-1:0]    REG_DIVISOR =   12'h004;
localparam  logic   [ADDR_W-1:0]    REG_TXDATA  =   12'h008;
localparam  logic   [ADDR_W-1:0]    REG_RXDATA  =   12'h00C;
localparam  logic   [ADDR_W-1:0]    REG_CMD     =   12'h010;

//--------------------------------------------------------------
//STATUS bit-poisition constants
//--------------------------------------------------------------
localparam  int unsigned    STATUS_CMD_READY        =   0;
localparam  int unsigned    STATUS_BUS_IDLE         =   1;
localparam  int unsigned    STATUS_DONE_TICK        =   2;
localparam  int unsigned    STATUS_ACK_VALID        =   3;
localparam  int unsigned    STATUS_ACK              =   4;
localparam  int unsigned    STATUS_RD_DATA_VALID    =   5;
localparam  int unsigned    STATUS_CMD_ILLEGAL      =   6;
localparam  int unsigned    STATUS_MASTER_RECEIVING =   7;

//--------------------------------------------------------------
//I2C core status/interface_signals
//--------------------------------------------------------------
logic   [BYTE_W-1:0]    i2c_rx_data;
logic                   i2c_cmd_ready;
logic                   i2c_cmd_illegal;
logic                   i2c_done_tick;
logic                   i2c_ack;
logic                   i2c_ack_valid;
logic                   i2c_rd_data_valid;
logic                   i2c_bus_idle;
logic                   i2c_master_receiving;

//--------------------------------------------------------------
//stored software-visible registers
//---------------------------------------------------------------
logic   [BYTE_W-1:0]    txdata_reg;
logic   [BYTE_W-1:0]    rxdata_reg;
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

//---------------------------------------------------------------
//Helper function: byte-write merge for 32-bit regs
//--------------------------------------------------------------
function    automatic   logic   [DATA_W-1:0]   merge_wstrb(
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
        
        return  (old_val    &   ~write_mask)    |   (new_val & write_mask);
    end
endfunction


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
assign  divisor_merged  =   merge_wstrb({{(DATA_W-DIVISOR_W){1'b0}},    divisor_reg},   req_wdata,   req_wstrb);
assign  cmd_merged      =   merge_wstrb('0, req_wdata,  req_wstrb);
//REG_CMD is action-oriented, so it is built from zero rather than merged into previous stored state
//Byte 0 (wstrb[0] must be present for a valid launch because cmd livs in bits [2:0]
assign  launch_cmd_fire =   wr_cmd_fire &&  i2c_cmd_ready && req_wstrb[0];
assign  launch_cmd      =   cmd_merged[CMD_W:0];
assign  launch_rd_last  =   cmd_merged[8];

//----------------------------------------------------------------------------
//Live Status assembly
//----------------------------------------------------------------------------
always_comb
begin
status_rdata                            =   '0; //clear status_rdata
status_rdata[STATUS_CMD_READY]          =   i2c_cmd_ready;
status_rdata[STATUS_BUS_IDLE]           =   i2c_bus_idle;
status_rdata[STATUS_DONE_TICK]          =   i2c_done_tick;
status_rdata[STATUS_ACK_VALID]          =   i2c_ack_valid;
status_rdata[STATUS_ACK]                =   i2c_ack;
status_rdata[STATUS_RD_DATA_VALID]      =   i2c_rd_data_valid;
status_rdata[STATUS_CMD_ILLEGAL]        =   i2c_cmd_illegal;
status_rdata[STATUS_MASTER_RECEIVING]   =   i2c_master_receiving;
end

//----------------------------------------------------------------------------
//Read mux /response decode
//----------------------------------------------------------------------------
logic   [DATA_W-1:0]    rdata_next;
logic                   err_next;

always_comb
begin
    rdata_next  =   '0;
    err_next    =   1'b0;

    unique  case    (req_addr)
        REG_STATUS:
        begin
            if(req_write)
            begin
                err_next    =   1'b1;
            end
            else
            begin
                rdata_next  =   status_rdata;
            end
        end

        REG_DIVISOR:
        begin
            rdata_next  =   {{(DATA_W-DIVISOR_W){1'b0}}, divisor_reg};
        end

        REG_TXDATA:
        begin
            rdata_next  =   {{(DATA_W-BYTE_W){1'b0}}, txdata_reg};
        end

        REG_RXDATA:
        begin
            if(req_write)
            begin
                err_next    =   1'b1;
            end
            else
            begin
                rdata_next  =   {{(DATA_W-BYTE_W){1'b0}}, rxdata_reg};
            end
        end

        REG_CMD:
        begin
            //Action register: reads are invalid, writea are valid only if
            //the core is ready in the same cycle
            if(!req_write)
            begin
                err_next    =   1'b1;
            end
            else if(!req_wstrb[0])
            begin
                err_next    =   1'b1;
            end
            else
            if(!i2c_cmd_ready)
            begin
                err_next    =   1'b1;
            end
        end

        default:
        begin
            err_next    =   1'b1;
        end
    endcase
end

//----------------------------------------------------------
//Stored register updates
//----------------------------------------------------------
always_ff   @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        txdata_reg  <=  '0;
        rxdata_reg  <=  '0;
        divisor_reg <=  MIN_DIVISOR;
    end
    else
    begin
        //Hold most recent RXbyte for software
        if(i2c_rd_data_valid)
        begin
            rxdata_reg  <=  i2c_rx_data;
        end

        if(wr_txdata_fire)
        begin
            txdata_reg  <=  txdata_merged[BYTE_W-1:0];
        end

        if(wr_divisor_fire)
        begin
            divisor_reg <=  divisor_merged[DIVISOR_W-1:0];
        end
    end
end

//------------------------------------------------------------
//Response channel
//------------------------------------------------------------
//One response per accepted request
//Response is held until rsp_ready
always_ff   @(posedge   clk or  negedge rst_n)
begin
    if(!rst_n)
    begin
        rsp_valid   <=  1'b0;
        rsp_rdata   <=  '0;
        rsp_err     <=  1'b0;
    end
    else
    begin
        if(rsp_fire)
            rsp_valid   <=  1'b0;

        if(req_fire)
        begin
            rsp_valid   <=  1'b1;
            rsp_rdata   <=  rdata_next;
            rsp_err     <=  err_next;
        end
    end
end

    // -------------------------------------------------------------------------
    // I2C core instance
    // -------------------------------------------------------------------------
    i2c_master #(
        .DIVISOR_W (DIVISOR_W),
        .BYTE_W    (BYTE_W),
        .CMD_W     (CMD_W),
        .MIN_DIVISOR(MIN_DIVISOR)) 
        u_i2c_master (
        .clk                (clk),
        .rst_n              (rst_n),
        .divisor            (divisor_reg),

        .rx_data_o          (i2c_rx_data),
        .tx_data_i          (txdata_reg),
        .rd_last_i          (launch_rd_last),

        .sda_in             (sda_in),
        .sda_out            (sda_out),
        .scl_in             (scl_in),
        .scl_out            (scl_out),

        .cmd                (launch_cmd),
        .cmd_illegal_o      (i2c_cmd_illegal),
        .cmd_valid_i        (launch_cmd_fire),
        .cmd_ready_o        (i2c_cmd_ready),

        .done_tick_o        (i2c_done_tick),
        .ack_o              (i2c_ack),
        .ack_valid_o        (i2c_ack_valid),
        .rd_data_valid_o    (i2c_rd_data_valid),
        .bus_idle_o         (i2c_bus_idle),
        .master_receiving_o (i2c_master_receiving)
    );

    assign master_receiving_o = i2c_master_receiving;

endmodule
