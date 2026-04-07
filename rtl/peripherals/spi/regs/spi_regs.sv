// spi_regs.sv
// -----------------------------------------------------------------------------
// MMIO register wrapper for the OpenCores SPI master:
// https://opencores.org/projects/spi_verilog_interface
// Licensed under LGPL
// -----------------------------------------------------------------------------
//
// CPU-facing register block for a simple SPI master peripheral.
//
// Design goals:
// - Deterministic one-byte-per-START behavior
// - Vendor SPI master treated as a black box
// - Sticky DONE and RX_VALID status bits
// - START / clear operations implemented as write-one pulse actions
// - Generic MMIO request/response interface for use behind an AXI-Lite wrapper
// - Separate interrupt enable bits for DONE and RX_VALID
// - Separate interrupt pending bits for DONE and RX_VALID
// - Level-sensitive IRQ output that remains asserted until software clears the
//   corresponding pending bit(s)
//
// Register map (32-bit words):
//
//   0x00  CTRL
//         bit 0   ENABLE        RW
//                 Enable the SPI peripheral
//         bit 1   START         W1P
//                 Launch one SPI byte transfer
//         bit 2   XFER_END      RW
//                 End-of-transfer qualifier for the NEXT launched byte:
//                 1 = this launched byte is the final byte of the transaction
//                 0 = keep the transaction open after this byte completes
//         bit 3   CLR_DONE      W1P
//                 Clear STATUS.DONE
//         bit 4   CLR_RX_VALID  W1P
//                 Clear STATUS.RX_VALID
//
//   0x04  STATUS
//         bit 0   BUSY          RO
//                 A byte is currently in flight; START is not accepted
//         bit 1   DONE          RO (sticky)
//                 Final byte of the transaction has completed
//         bit 2   RX_VALID      RO (sticky)
//                 RXDATA holds a received byte from the most recent completed
//                 SPI byte transfer
//         bit 3   TX_READY      RO
//                 Vendor SPI core is ready to accept another byte
//         bit 4   ENABLED       RO
//                 Current value of CTRL.ENABLE
//         bit 5   CS_ACTIVE     RO
//                 Chip select is currently asserted at the SPI pins
//         bit 6   XFER_OPEN     RO
//                 A transaction is currently open. This may remain set between
//                 bytes during a multi-byte transfer even when BUSY=0.
//
//   0x08  TXDATA
//         bits [7:0]  TX byte   RW
//         Holding register for the next byte to be launched
//
//   0x0C  RXDATA
//         bits [7:0]  RX byte   RO
//         Most recently received byte
//
//   0x10  IRQ_EN
//         bit 0   DONE_IE       RW
//                 Interrupt enable for DONE event
//         bit 1   RX_VALID_IE   RW
//                 Interrupt enable for RX_VALID event
//
//   0x14  IRQ_STATUS
//         bit 0   DONE_IP       RO/W1C
//                 Interrupt pending for DONE event
//         bit 1   RX_VALID_IP   RO/W1C
//                 Interrupt pending for RX_VALID event
//
// Policy / behavior:
// - One START launches exactly one SPI byte
// - START is accepted only when:
//     * ENABLE = 1
//     * BUSY   = 0
//     * vendor core TX interface is ready
// - BUSY is byte-scoped:
//     * BUSY = 1 while the current byte is in flight
//     * BUSY = 0 once that byte completes
// - XFER_OPEN is transaction-scoped:
//     * set when a byte is launched
//     * remains set across intermediate bytes of a multi-byte transaction
//     * clears only when the launched final byte completes
// - CTRL.XFER_END applies to the NEXT launched byte
// - The launched byte captures its own XFER_END qualifier at launch time;
//   software may update CTRL.XFER_END later for the following byte without
//   changing the completion behavior of the byte already in flight
// - TXDATA may be rewritten while BUSY=1; it serves as a staging register for
//   the next byte and does not affect the byte already launched
// - CTRL.ENABLE may only be changed when no transaction is open
// - CLR_DONE / CLR_RX_VALID are allowed at any time
//
// Interrupt behavior:
// - RX_VALID event occurs after every completed byte
// - DONE event occurs only after the final byte of a transaction
// - IRQ is level-sensitive:
//     IRQ = (DONE_IE && DONE_IP) || (RX_VALID_IE && RX_VALID_IP)
// - Software must clear IRQ_STATUS pending bits explicitly
//
// Notation:
// - RW     = normal read/write storage bit
// - RO     = read-only from software perspective
// - W1P    = write-one pulse; action bit, not stored
// - RO/W1C = sticky status/pending bit; write 1 clears it

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
    input   logic                       spi_miso,
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
    localparam  int STATUS_XFER_OPEN_BIT =   6;    

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
    // Generic MMIO acceptance
    //---------------------------------------------------------------
    // This block allows only one outstanding MMIO request/response pair.
    // A new request is accepted only when no response is currently pending.
    assign req_ready = !rsp_valid;

    logic   req_fire;
    logic   wr_fire;
    
    assign  req_fire    =   req_valid   &&  req_ready;
    assign  wr_fire     =   req_fire    &&  req_write;

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
    // Pulse commands generated from CTRL writes
    //------------------------------------------------------------------
    logic   start_cmd_fire;
    logic   clr_done_cmd_fire;
    logic   clr_rx_valid_cmd_fire;

    assign  start_cmd_fire  =   
        wr_ctrl_fire    &&  req_wstrb[0]    &&  req_wdata[CTRL_START_BIT];

    assign  clr_done_cmd_fire   = 
        wr_ctrl_fire    &&  req_wstrb[0]    &&  req_wdata[CTRL_CLR_DONE_BIT];

    assign  clr_rx_valid_cmd_fire   =
        wr_ctrl_fire    &&  req_wstrb[0]    &&  req_wdata[CTRL_CLR_RX_VALID_BIT];

    //--------------------------------------------------------------------
    //Stored control / data registers
    //------------------------------------------------------------------
    logic   ctrl_enable;
    logic   ctrl_xfer_end;
    logic   [SPI_DW-1:0] txdata_reg;
    logic   [SPI_DW-1:0] rxdata_reg;
    logic   start_pending; //mode 1: cpol=0, cpha=1 needs a larger window for core_wready
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
    logic                   core_rvalid;

    //----------------------------------------------------------------
    //Internal event naming
    //----------------------------------------------------------------
    logic   start_fire;
    logic   tx_fire;
    logic   rx_fire;

    //----------------------------------------------------------------
    //xfer_open register for multi-byte transactions
    //----------------------------------------------------------------
    //xfer_open = 1: CS-held transaction is still open
    //xfer_open = 0: no transaction in progress
    logic xfer_open; 

    //----------------------------------------------------------------
    //Launch-time latched final-byte qualifier
    //----------------------------------------------------------------
    //keep track to keep the xfer_end value that was present when
    //corresponding byte was launched
    logic launched_xfer_end;
    logic start_xfer_end;

    assign start_xfer_end   =   (wr_ctrl_fire && req_wstrb[0]) ?  req_wdata[CTRL_XFER_END_BIT]    : ctrl_xfer_end;

    //----------------------------------------------------------------
    //Transfer-launch acceptance policy
    //----------------------------------------------------------------
    //start_cmd_fire means software asked to start
    //start_fire Means the wrapper accepted the request
    //
    //A START is accepted only when:
    // - peripheral is enabled
    // - no transfer is currently in progress
    // - vendor core is ready to accept a new word
    assign start_fire   =   start_pending  && ctrl_enable  && !busy && core_wready;

    //One accepted START launches one SPI word.
    assign tx_fire  =   start_fire;

    //The vendor core assesrts )rvalid when a received word is available
    //In this wrapper, that also means the one-word transfer is complete
    assign rx_fire  =   core_rvalid;

    //fix a glitch on mode 3, and makes the module more robust
    //this wrapper will hold the start request until the vendor core is actually ready
    //software no longer has to "hit" core_ready exactly
    always_ff @(posedge  clk  or negedge rst_n)
    begin
        if(!rst_n)
        begin
            start_pending   <=  1'b0;
        end
        else
        begin
            //Latch a START request wehn software asks for one
            // and no byte is currently in flight.
            if(start_cmd_fire && ctrl_enable && !busy)
            begin
                start_pending   <=1'b1;
            end

            //Clear it once the byte is actually launched.
            if(tx_fire)
            begin
                start_pending   <=  1'b0;
            end
        end
    end

    //------------------------------------------------------------------
    // Vendor core drive signals
    //------------------------------------------------------------------------------------------------------------------------
    // core_wvalid is a one-cycle pulse when a byte transfer is launched.
    // core_transfer_end presents the current launch qualifier on the launch
    // cycle, and otherwise holds the qualifier associated with the byte
    // already in flight.
    assign  core_wvalid         =   tx_fire;
    assign  core_wdata          =   txdata_reg[SPI_DW-1:0];
    assign  core_transfer_end   =   tx_fire ?   start_xfer_end   :   launched_xfer_end;

    //------------------------------------------------------------------
    //CTRL and TXDATA storage
    //------------------------------------------------------------------
            // CTRL write policy:
            // - ENABLE is writable only when no transaction is open
            // - XFER_END may be updated between bytes to prepare the next launch
            // TXDATA is a staging register for the next byte.
            // Writing TXDATA while BUSY=1 is safe; the in-flight byte has already
            // been captured by the vendor core on tx_fire.
    always_ff @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            ctrl_enable     <=  1'b0;
            ctrl_xfer_end   <=  1'b1;   //safe default for one-word transactions
            txdata_reg      <=  '0;
        end
        else
        begin
            //CTRL RW policy:
            // -ENABLE is only writable while idle
            // -ctrl_xfer_end is now writable outside iddle to allow multibyte xfers
            // -This prevents active transfer behavior from changing mid-transaction
            if(wr_ctrl_fire  &&  req_wstrb[0])
            begin
                if(!xfer_open)
                begin
                    ctrl_enable <=  req_wdata[CTRL_ENABLE_BIT];
                end
                ctrl_xfer_end   <=  req_wdata[CTRL_XFER_END_BIT];
            end

            //TXDATA is just a holding register for the next transfer
            //allowing writes while busy is safe; it does not affect an already
            //launched transfer because core_wdata is only sampled on tx_fire.
            if(wr_txdata_fire   &&  req_wstrb[0])
            begin
                txdata_reg  <=  req_wdata[7:0];
            end
        end
    end

    //--------------------------------------------------------------------------
    //STATUS bit storage
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            busy            <=  1'b0;
            xfer_open       <=  1'b0;
            launched_xfer_end   <=  1'b1;
            done            <=  1'b0;
            rx_valid        <=  1'b0;
            rxdata_reg      <=  '0;
        end
        else
        begin
            //Launching a byte opnes/continues a transaction
            // - BUSY becomes 1 and can't accept new data
            // - transaction is open
            // - latch wheter this launched byte is the final byte

            if(tx_fire)
            begin
                busy        <=  1'b1;
                xfer_open   <=  1'b1;
                launched_xfer_end   <=  start_xfer_end;
            end

            // A received byte completes the current in-flight byte.
            // RX_VALID is asserted for every completed byte.
            // DONE is asserted only when the launched byte was marked final.
            if(rx_fire)
            begin
                busy        <=  1'b0;
                rx_valid    <=  1'b1;
                rxdata_reg  <=  core_rdata[7:0];

                if(launched_xfer_end)
                begin
                    done        <=  1'b1;
                    xfer_open   <=  1'b0;
                end
                else
                begin
                    xfer_open   <=  1'b1; 
                end
            end

            //Sticky STATUS flags are cleared explicityly by sofware through CTRL
            if(clr_done_cmd_fire)
            begin
                done    <=  1'b0;
            end

            if(clr_rx_valid_cmd_fire)
            begin
                rx_valid    <=  1'b0;
            end
        end
    end


    //---------------------------------------------------------------------------
    //IRQ enable storage
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            irq_en_done     <=  1'b0;
            irq_en_rx_valid <=  1'b0;
        end
        else
        begin
            if(wr_irq_en_fire   &&  req_wstrb[0])
            begin
                irq_en_done     <=  req_wdata[IRQ_DONE_BIT];
                irq_en_rx_valid <=  req_wdata[IRQ_RX_VALID_BIT];
            end
        end
    end

    //--------------------------------------------------------------------------
    //IRQ enable storage
    //--------------------------------------------------------------------------
    //These are separate from STATUS.DONE and STATUS.RX_VALID on purpose.
    //
    //Why are they separated
    // - STATUS bits tell software what happened in the peripheral
    // - IRQ pending bits tell the interrupt controller / ISR what must be acknowledge
    // - Software cna clear interrupt pending without necessarily clearing STATUS
    // and vice versa
    always_ff   @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            irq_done_pending        <=  1'b0;
            irq_rx_valid_pending    <=  1'b0;
        end
        else
        begin
            //Hardware sets pending bits when the event occurs.
            if(rx_fire)
            begin
                irq_rx_valid_pending    <=  1'b1;

                if(launched_xfer_end)
                begin
                    irq_done_pending        <=  1'b1;
                end
            end

            //Sofware clears pending bits by writing 1 to IRQ_STATUS (W1C)
            if(wr_irq_status_fire && req_wstrb[0])
            begin
                if(req_wdata[IRQ_DONE_BIT])
                begin
                    irq_done_pending    <=  1'b0;
                end

                if(req_wdata[IRQ_RX_VALID_BIT])
                begin
                    irq_rx_valid_pending    <=  1'b0;
                end
            end
        end
    end


//------------------------------------------------------------------------
//Combine interrupt output
//------------------------------------------------------------------
//Level-sensitive interrupt:
//irq remain asserted while t least one enabled pending source is active.
//
//This is usually preferable for CPU integration because it avoids missed
//one-cycle pulses and cleanly supports software acknowledgement
assign  irq =   (irq_en_done        &&  irq_done_pending)   ||
                (irq_en_rx_valid    &&  irq_rx_valid_pending);

//----------------------------------------------------------------------
//Read mux
//----------------------------------------------------------------------
logic   [DATA_W-1:0]    rdata_next;
logic                   err_next;

always_comb
begin
    rdata_next  =   '0;
    err_next    =   1'b0;

    unique  case    (req_addr)
        REG_CTRL:
        begin
            //W1P bits read back as 0 because they are actions, not storage.
            rdata_next[CTRL_ENABLE_BIT]     =   ctrl_enable;
            rdata_next[CTRL_XFER_END_BIT]   =   ctrl_xfer_end;
        end

        REG_STATUS:
        begin
            rdata_next[STATUS_BUSY_BIT]      = busy;
            rdata_next[STATUS_DONE_BIT]      = done;
            rdata_next[STATUS_RX_VALID_BIT]  = rx_valid;
            rdata_next[STATUS_TX_READY_BIT]  = core_wready;
            rdata_next[STATUS_ENABLED_BIT]   = ctrl_enable;
            rdata_next[STATUS_CS_ACTIVE_BIT] = ~spi_cs_n;
            rdata_next[STATUS_XFER_OPEN_BIT]    =   xfer_open;
        end

        REG_TXDATA:
        begin
            rdata_next[7:0] = txdata_reg;
        end

        REG_RXDATA:
        begin
            rdata_next[7:0] = rxdata_reg;
        end

        REG_IRQ_EN:
        begin
            rdata_next[IRQ_DONE_BIT]     = irq_en_done;
            rdata_next[IRQ_RX_VALID_BIT] = irq_en_rx_valid;
        end

        REG_IRQ_STATUS:
        begin
            rdata_next[IRQ_DONE_BIT]     = irq_done_pending;
            rdata_next[IRQ_RX_VALID_BIT] = irq_rx_valid_pending;
        end

        default:
        begin
            rdata_next = '0;
            err_next   = 1'b1;
        end
    endcase
end

//-----------------------------------------------------------------
//Response channel
//-----------------------------------------------------------------
//One response per accepted request
//Response is held until rsp_ready
logic   [DATA_W-1:0]    rsp_rdata_r;
logic                   rsp_err_r;

always_ff   @(posedge   clk or  negedge rst_n)
begin
    if(!rst_n)
    begin
        rsp_valid   <=  1'b0;
        rsp_rdata_r <=  '0;
        rsp_err_r   <=  1'b0;
    end
    else
    begin
        //Existing response accepted by upstream
        if(rsp_valid    &&  rsp_ready)
        begin
            rsp_valid   <=  1'b0;
        end

        //New request accepted only if no response is currently outstanding
        if(!rsp_valid   && req_fire)
        begin
            rsp_valid       <=  1'b1;
            rsp_rdata_r     <=  rdata_next;
            rsp_err_r       <=  err_next;
        end
    end
end

assign  rsp_rdata   =   rsp_rdata_r;
assign  rsp_err     =   rsp_err_r;

//------------------------------------------------------------------
//Vendor SPI master instantiation
//------------------------------------------------------------------
//Treat this as a black box:
//  - I_wvalid  launches a word transfer
//  - O_wready says the core can accpet a word
//  - O_rvalid/O_rdata indicate received data data completion
//  - O_csn / O_sclk / O_mosi are the SPI outputs
spi_master  #(
    .CPOL(CPOL),
    .CPHA(CPHA),
    .BITORDER(BITORDER),
    .DATAWIDTH(SPI_DW),
    .CLKDIV(CLKDIV))
u_spi_master(
    .I_clk(clk),
    .I_rstn(rst_n),

    .I_wvalid(core_wvalid),
    .I_transfer_end(core_transfer_end),
    .I_wdata(core_wdata),

    .O_wready(core_wready),
    .O_rdata(core_rdata),
    .O_rvalid(core_rvalid),

    .O_csn(spi_cs_n),
    .O_sclk(spi_sclk),
    .O_mosi(spi_mosi),
    .I_miso(spi_miso));    

endmodule