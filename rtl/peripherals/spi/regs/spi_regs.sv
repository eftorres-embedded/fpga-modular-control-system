//spi_regs.sv
// -----------------------------------------------------------------------------
// This module wraps the SPI core from:
// https://opencores.org/projects/spi_verilog_interface
// Licensed under LGPL
// -----------------------------------------------------------------------------
//
//CPU-facing MMIO restister block for a simple SPI master perifpheral
//Version 1 design goals:
// -Deterministic, one-byte-per-start behavior
// -Vendor SPI master treated as a black box
// -Sticky DONE and RX_VALID status bit
// -START / Clear bits are write-one pulse actions
// -AXI-Lite Wrapper talks to this block through a generic MMIO interface
// -DONE_IE and RX_VALID_IE are spearate interrupt-enable bits
// -DONE_IP and RX_VALID_IP are separate interrupt-pending bits
// -irq output is level-sensitive and stays asserted until software clears pending bits
//
// -
//
//Register map (32-bit words):
//  0x00    CTRL
//          bit 0   ENABLE          WR      Turn SPI module on
//          bit 1   START           W1P     Start transaction
//          bit 2   XFER_END        WR      Default:1 > Realease CS after transfer; 0 > CS stays low
//          bit 3   CLR_DONE        W1P     Clears the DONE flag from STATUS register
//          bit 4   CLR_RX_VALID    W1P     Clears the RX_VALID flag from  STATUS register
//
//  0X04    STATUS
//          bit 0   BUSY            RO      Transactions is in progress
//          bit 1   DONE            RO      Transaction has finished    (sticky)
//          bit 2   RX_VALID        RO      Data received is valide     (sticky)
//          bit 3   TX_READY        RO      SPI module can send another word
//          bit 4   ENABLED         RO      SPI module is on (enabled)
//          bit 5   CS_ACTIVE       RO      CS is asserted
//
//  0x08    TXDATA
//          bits[7:0] TX byte       WO
//
//  0x0C    RXDATA
//          bits[7:0] RX byte       RO
//
//  0x10    IRQ_EN
//          bit 0   DONE_IE         RW      interrupt enable for transfer done
//          bit 1   RX_VALID_IE     RW      interrupt enable for RX valid
//
//  0x14    IRQ_STATUS
//          bit 0   DONE_IP         RO/W1C  interrupt   pending for done
//          bit 1   RX_VALID_IP     RO/W1C  interrupt pending for rx valid
//
// -----------------------Policy--------------------------
//One START sends exactly one SPIO word
//START is ignored while buys
//ENABLE and XFER_END may only be updated while idle
//TXDATA may be updated while busy; it applies to the next transfer
//CLR_DONE / CLR_RX_VALID are allowed anytime
//
//Notation:
// -RW      =   normal read/write storage bit
// -RO      =   read-only from software perspective
// -W1P     =   write-one pulse; action bit, not stored
// -RO/W1C  =   read-only sticky bit; write 1 clears it    
//
//Notes:
// -XFER_END should stay 1 in software for sing-word transaction
// -XFER_END=0 is a future feautrue behavior for multi-word CS hold
//----------------------------------------------------------------------

module  spi_regs    #(
    parameter   int unsigned    ADDR_W      =   12,
    parameter   int unsigned    DATA_W      =   32,

    //Fixed hardware configuratin for vendor core
    parameter   bit             CPOL        =   1'b0,
    parameter   bit             CPHA        =   1'b1,
    parameter   string          BITORDER    =   "MSB_FIRST",
    parameter   int unsigned    SPI_DW      =   8,
    parameter   int unsigned    CLKDIV      =   8)

    (
    input   logic               clk,
    input   logic               rst_n,
    
    //--------------------------------------------------------
    //Generic MMIO request / response interface
    //--------------------------------------------------------
    input   logic                       req_valid,
    output  logic                       req_ready,
    input   logic                       req_write,
    input   logic   [ADDR_W-1:0]        req_addr,
    input   logic   [DATA_W-1:0]        req_wdata,
    input   logic   [(DATA_W/8)-1:0]    req_wstrb,

    output  logic                       rsp_valid,
    input   logic                       rsp_ready,
    output  logic   [DATA_W-1:0]        rsp_rdata,
    output  logic                       rsp_err,

    output  logic                       irq,

    //--------------------------------------------------------
    //External SPI pins
    //--------------------------------------------------------
    output  logic                       spi_sclk,
    output  logic                       spi_mosi,
    input   loigc                       spi_miso,
    output  logic                       spi_cs_n);

    //--------------------------------------------------------------
    //Register offsets
    //--------------------------------------------------------------
    localparam  logic   [ADDR_W-1:0]    REG_CTRL            =   'h0;
    localparam  logic   [ADDR_W-1:0]    REG_STATUS          =   'h4;
    localparam  logic   [ADDR_W-1:0]    REG_TXDATA          =   'h8;
    localparam  logic   [ADDR_W-1:0]    REG_RXDATA          =   'hC;
    localparam  logic   [ADDR_W-1:0]    REG_IRQ_EN          =   'h10;
    localparam  logic   [ADDR_W-1:0]    REG_IRQ_STATUS      =   'h14;

    //--------------------------------------------------------------
    //CTRL bits
    //--------------------------------------------------------------
    localparam  int CTRL_ENABLE_BIT         =   0;
    localparam  int CTRL_START_BIT          =   1;
    localparam  int CTRL_XFER_END_BIT       =   2;
    localparam  int CTRL_CLR_DONE_BIT       =   3;
    localparam  int CTRL_CLR_RX_VALID_BIT   =   4;

    //--------------------------------------------------------------
    //STATUS bits
    //--------------------------------------------------------------
    localparam  int STATUS_BUSY_BIT     =   0;
    localparam  int STATUS_DONE_BIT     =   1;
    localparam  int STATUS_RX_VALID_BIT =   2;
    localparam  int STATUS_TX_READY_BIT =   3;
    localparam  int STATUS_ENABLED_BIT  =   4;
    localparam  int STATUS_CS_ACTIVE_BIT=   5;

    //--------------------------------------------------------------
    //IRQ_EN / IRQ_STATUS bits
    //--------------------------------------------------------------
    localparam  int IRQ_DONE_BIT        =   0;
    localparam  int IRQ_RX_VALID_BIT    =   1;

    //--------------------------------------------------------------
    //Procted from using ilegal data bus width and spi data with
    //--------------------------------------------------------------
    initial
    begin
        if(DATA_W!=32)
        begin
            $error("spi_regs: implementation expects DATA_W == 32");
        end

        if(SPI_DW>8)
        begin
            $error("spi_regs: regsiter packing expects SPI_DW <= 8");
        end
    end

    //---------------------------------------------------------------
    //Generic MMIO accpetance
    //---------------------------------------------------------------
    //This block is simple and doesn't back-pressures requests internally.
    //One response is generated per accepted request
    assign req_ready = 1'b1;

    logic   req_fire;
    logic   wr_fire;
    logic   rd_fire;
    
    assign  req_fire    =   req_valid   &&  req_ready;
    assign  wr_fire     =   req_fire    &&  req_write;
    assign  rd_fire     =   req_fire    &&  !req_write;

    //-----------------------------------------------------------------
    //Write decode helpers
    //-----------------------------------------------------------------
    logic   wr_ctrl_fire;
    logic   wr_txdata_fire;
    logic   wr_irq_en_fire;
    logic   wr_irq_status_fire;

    assign  wr_ctrl_fire        =   wr_fire &&  (req_addr   ==  REG_CTRL);
    assign  wr_txdata_fire      =   wr_fire &&  (req_addr   ==  REG_TXDATA);
    assign  wr_irq_en_fire      =   wr_fire &&  (req_addr   ==  REG_IRQ_EN);
    assign  wr_irq_status_fire  =   wr_fire &&  (req_addr   ==  REG_IRQ_STATUS);

    //------------------------------------------------------------------
    //Pluse command from CTRL writes
    //------------------------------------------------------------------
    logic   start_comd_fire;
    logic   clr_done_cmd_fire;
    logic   clr_rx_valid_cmd_fire;

    assign  start_cmd_fire  =   
        wr_ctrl_fire    &&  req_wstrb[0]    &&  req_wdata[CTRL_START_BIT];

    assign  clr_done_fire   = 
        wr_ctrl_fire    &&  req_wstrb[0]    &&  req_wdata[CTRL_CLR_DONE_BIT];

    assign  clr_rx_valid_cmd_fire   =
        wr_ctrl_fire    &&  req_wstrb[0]    &&  req_wdata[CTRL_CRL_RX_VALAID_BIT];

    //--------------------------------------------------------------------
    //Stored control / data registers
    //------------------------------------------------------------------
    logic   ctrl_enable;
    logic   ctrl_xfer_end;
    logic   [SPI_DW-1:0] txdata_reg;
    logic   [SPI_DW-1:0] rxdata_reg;

    //------------------------------------------------------------------
    //Sticky status bits visible in STATUS register
    //------------------------------------------------------------------
    logic   busy;
    logic   done;
    logic   rx_valid;

    //-------------------------------------------------------------------
    //Interrupt enable bits (software-controlled)
    //------------------------------------------------------------------
    logic   irq_en_done;
    logic   irq_en_rx_valid;

    //------------------------------------------------------------------
    //Interrupt pending bits (hardware sets, software clears with W1C)
    //------------------------------------------------------------------
    logic   irq_done_pending;
    logic   irq_rx_valid_pending;

    //-----------------------------------------------------------------
    //Vendor SPI core interface
    //-----------------------------------------------------------------
    logic                   core_wvalid;
    logic                   core_wready;
    logic   [SPI_DW-1:0]    core_wdata;
    logic                   core_transfer_end;

    logic   [SPI_DW-1:0]    core_rdata;
    logic   [SPI_DW-1:0]    core_rvalid;

    //-----------------------------------------------------------------
    //Internal event naming
    //----------------------------------------------------------------
    logic   start_fire;
    logic   tx_fire;
    logic   rx_fire;

    //----------------------------------------------------------------
    //Transfer-launch acceptance policy
    //----------------------------------------------------------------
    //start_cmd_fire means software asked to start
    //start_fire Means the wrapper accepted the request
    //
    //A START is accepted only when:
    // - peripheral is enabled
    // - no transfer is currently in progress
    // - vendor core is ready to accpt a new word
    assign start_fire   =   start_cmd_fire  && ctrl_enable  && !busy    && core_wready;

    //One accepted START launches one SPI word.
    assign tx_fire  =   start_fire;

    //The vendor core assesrts )rvalid when a received word is available
    //In this wrapper, that also means the one-word transfer is complete
    assign rx_fire  =   core_rvalid;

    //------------------------------------------------------------------
    //Vendor core drie signals
    //------------------------------------------------------------------
    //core_wvalid is a one-cycle pulse when a transfer is launched
    assign  core_wvalid         =   tx_fire;
    assign  core_wdata          =   tx_data_reg[SPI_DW-1:0];
    assign  core_transfer_end   =   ctrl_xfer_end;

    //------------------------------------------------------------------
    //CTRL and TXDATA storage
    //------------------------------------------------------------------