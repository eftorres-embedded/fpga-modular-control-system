//axi_lite_i2c.sv
//------------------------------------------------------------------------------
// AXI4-Lite slave wrapper for i2c_regs.sv
//------------------------------------------------------------------------------
//
// Purpose:
// - Present a standard AXI4-Lite slave interface at the top level
// - Bridge AXI4-Lite transactions into the internal generic MMIO interface
// - Instantiate i2c_regs.sv without modifying it
//
// Design notes:
// - One internal MMIO request is active at a time
// - AXI write address (AW) and write data (W) are captured independently
// - A write request is issued only after both AW and W have been captured
// - Read requests are issued from AR
// - Writes are given priority over reads when both are pending
// - Response mapping:
//     rsp_err = 0 -> AXI OKAY   (2'b00)
//     rsp_err = 1 -> AXI SLVERR (2'b10)
//
// Two sets of registers are used:
// the *_hold_* set connects to the AXI side; these are the pieces that need
// "assembly"
// the *_pending_* set is an assembled MMIO command waiting to be accepted
// by i2c_regs.sv
//------------------------------------------------------------------------------
//
// I2C register map note
// ---------------------
// The actual register map is implemented inside i2c_regs.sv.
// The byte offsets visible through AXI-Lite are:
//
//   0x00  REG_STATUS
//   0x04  REG_DIVISOR
//   0x08  REG_TXDATA
//   0x0C  REG_RXDATA
//   0x10  REG_CMD
//
// REG_CMD fields:
//   [2:0]  cmd
//   [8]    rd_last
//
//------------------------------------------------------------------------------

module  axi_lite_i2c    #(
    parameter   int unsigned            ADDR_W      =   12,
    parameter   int unsigned            DATA_W      =   32,
    parameter   int unsigned            BYTE_W      =   8,
    parameter   int unsigned            CMD_W       =   3,
    parameter   int unsigned            DIVISOR_W   =   16,
    parameter  logic   [DIVISOR_W-1:0] MIN_DIVISOR =   'd1)
    (
    input   logic                       clk,
    input   logic                       rst_n,

    //------------------------------------------------------------------
    //AXI4-Lite slave interface
    //------------------------------------------------------------------
    //Write address channel
    input   logic   [ADDR_W-1:0]        s_axil_awaddr,
    input   logic   s_axil_awvalid,
    output  logic                       s_axil_awready,

    //Write data channel
    input   logic   [DATA_W-1:0]        s_axil_wdata,
    input   logic   [(DATA_W/8)-1:0]    s_axil_wstrb,
    input   logic                       s_axil_wvalid,
    output  logic                       s_axil_wready,

    //Write response channel
    output  logic   [1:0]               s_axil_bresp,
    output  logic                       s_axil_bvalid,
    input   logic                       s_axil_bready,

    //Read address channel
    input   logic   [ADDR_W-1:0]        s_axil_araddr,
    input   logic                       s_axil_arvalid,
    output  logic                       s_axil_arready,

    //Read data channel
    output  logic   [DATA_W-1:0]        s_axil_rdata,
    output  logic   [1:0]               s_axil_rresp,
    output  logic                       s_axil_rvalid,
    input   logic                       s_axil_rready,

    //----------------------------------------------------------------
    //I2C top-level signals
    //----------------------------------------------------------------
    input   logic                       sda_in,
    output  logic                       sda_out,
    input   logic                       scl_in,
    output  logic                       scl_out,
    output  logic                       master_receiving_o);

    //---------------------------------------------------------------
    //Local parameers
    //-----------------------------------------------------------------
    localparam  logic   [1:0]   AXI_RESP_OKAY   =   2'b00;
    localparam  logic   [1:0]   AXI_RESP_SLVERR =   2'b10;

    //-----------------------------------------------------------------
    //One-deep holding registers for AXI channels
    //
    //These decouple the AXI channels from the internal MMIO request channel
    //AW and W may arrive in different cycles; we capture them independently
    //ARVALID can arrive while still holding a write address, etc
    //-------------------------------------------------------------------
    logic                       aw_hold_valid;
    logic   [ADDR_W-1:0]        aw_hold_addr;

    logic                       w_hold_valid;
    logic   [DATA_W-1:0]        w_hold_data;
    logic   [(DATA_W/8)-1:0]    w_hold_strb;

    logic                       ar_hold_valid;
    logic   [ADDR_W-1:0]        ar_hold_addr;

    //--------------------------------------------------------------------
    //AXI handshake aliases
    //--------------------------------------------------------------------
    logic   aw_fire;
    logic   w_fire;
    logic   ar_fire;
    logic   b_fire;
    logic   r_fire;

    assign  aw_fire =   s_axil_awvalid  &&  s_axil_awready;
    assign  w_fire  =   s_axil_wvalid   &&  s_axil_wready;
    assign  ar_fire =   s_axil_arvalid  &&  s_axil_arready;
    assign  b_fire  =   s_axil_bvalid   &&  s_axil_bready;
    assign  r_fire  =   s_axil_rvalid   &&  s_axil_rready;

    //----------------------------------------------------------------------
    //Internal MMIO interface to i2c_regs.sv
    //----------------------------------------------------------------------
    logic                       req_valid;
    logic                       req_ready;
    logic                       req_write;
    logic   [ADDR_W-1:0]        req_addr;
    logic   [DATA_W-1:0]        req_wdata;
    logic   [(DATA_W/8)-1:0]    req_wstrb;

    logic                       rsp_valid;
    logic                       rsp_ready;
    logic   [DATA_W-1:0]        rsp_rdata;
    logic                       rsp_err;

    logic                       axi_resp_busy;

    //----------------------------------------------------------------------
    //MMIO request staging
    //
    //req_* is driven from registered staging fields below.
    //This makes the bridge easy to reason about and avoids confuisng
    //combinational request generation
    //----------------------------------------------------------------------
    logic                       req_pending_valid;
    logic                       req_pending_write;
    logic   [ADDR_W-1:0]        req_pending_addr;
    logic   [DATA_W-1:0]        req_pending_wdata;
    logic   [(DATA_W/8)-1:0]    req_pending_wstrb;

    //Tracks the request that has been accepted by i2c_regs and is awaiting a response
    logic                       mmio_busy;
    logic                       mmio_active_write;

    logic   req_fire;
    logic   rsp_fire;

    assign  req_fire    =   req_valid   &&  req_ready;
    assign  rsp_fire    =   rsp_valid   &&  rsp_ready;

    assign  req_valid   =   req_pending_valid;
    assign  req_write   =   req_pending_write;
    assign  req_addr    =   req_pending_addr;
    assign  req_wdata   =   req_pending_wdata;
    assign  req_wstrb   =   req_pending_wstrb;

    //In this wrapper, only one MMIO transaction can be active at a time
    //Once a transaction has been accepted by i2c_regs, keep rsp_ready high
    //until the response returns.
    assign  rsp_ready   =   mmio_busy;
    assign  axi_resp_busy   =   s_axil_bvalid || s_axil_rvalid;

    //--------------------------------------------------------------------
    //AXI ready generation
    //
    //One-deep channel buffering:
    //  - Accept AW only when AW holding register is emtpy
    //  - Accept W  only when W holding register is empty
    //  - Accpet AR only when AR holding register is empty 
    //--------------------------------------------------------------------
    always_comb
    begin
        s_axil_awready  =   !aw_hold_valid;
        s_axil_wready   =   !w_hold_valid;
        s_axil_arready  =   !ar_hold_valid;
    end

    //--------------------------------------------------------------------
    //Request issue decisions
    //
    //Writes are prioritized over reads
    //
    //Launch_write_req
    //Both AW and W have been captured, and no internal transaction is active
    //
    //Launch_read_req:
    //AR has been captured, no write is waiting to launch, and no internal transaction is active
    //--------------------------------------------------------------------
    logic   launch_write_req;
    logic   launch_read_req;

    always_comb
    begin
        launch_write_req    =   1'b0;
        launch_read_req     =   1'b0;

        if(!req_pending_valid   &&  !mmio_busy && !axi_resp_busy)
        begin
            if(aw_hold_valid  &&  w_hold_valid)
            begin
                launch_write_req    =   1'b1;
            end
            else if(ar_hold_valid)
            begin
                launch_read_req =   1'b1;
            end
        end
    end

    //-------------------------------------------------------------------
    //Sequential control
    //-------------------------------------------------------------------
    always_ff   @(posedge   clk or  negedge rst_n)
    begin
        if(!rst_n)
        begin
            //-----------------------------------------------------------
            //Reset: clear AXI holding regs
            //-----------------------------------------------------------
            aw_hold_valid   <=  1'b0;
            aw_hold_addr    <=  '0;

            w_hold_valid    <=  1'b0;
            w_hold_data     <=  '0;
            w_hold_strb     <=  '0;

            ar_hold_valid   <=  1'b0;
            ar_hold_addr    <=  '0;

            //-----------------------------------------------------------
            //Reset: clear MMIO staging/tracking
            //----------------------------------------------------------
            req_pending_valid   <=  1'b0;
            req_pending_write   <=  1'b0;
            req_pending_addr    <=  '0;
            req_pending_wdata   <=  '0;
            req_pending_wstrb   <=  '0;

            mmio_busy           <=  1'b0;
            mmio_active_write   <=  1'b0;

            //-----------------------------------------------------------
            //Reset: clear AXI responses
            //-----------------------------------------------------------
            s_axil_bvalid       <=  1'b0;
            s_axil_bresp        <=  AXI_RESP_OKAY;

            s_axil_rvalid       <=  1'b0;
            s_axil_rresp        <=  AXI_RESP_OKAY;
            s_axil_rdata        <=  '0;
        end
        else
        begin
            //------------------------------------------------------------
            //Capture AXI write address channel
            //------------------------------------------------------------
            if(aw_fire)
            begin
                aw_hold_valid   <=  1'b1;
                aw_hold_addr    <=  s_axil_awaddr;
            end

            //-------------------------------------------------------------
            //Capture AXI write data channel
            //------------------------------------------------------------
            if(w_fire)
            begin
                w_hold_valid    <=  1'b1;
                w_hold_data     <=  s_axil_wdata;
                w_hold_strb     <=  s_axil_wstrb;
            end

            //-------------------------------------------------------------
            //Capture AXI read address channel
            //-------------------------------------------------------------
            if(ar_fire)
            begin
                ar_hold_valid   <=  1'b1;
                ar_hold_addr    <=  s_axil_araddr;
            end

            //--------------------------------------------------------------
            //Launch a staged internal MMIO write request
            //-------------------------------------------------------------
            if(launch_write_req)
            begin
                req_pending_valid   <=  1'b1;
                req_pending_write   <=  1'b1;
                req_pending_addr    <=  aw_hold_addr;
                req_pending_wdata   <=  w_hold_data;
                req_pending_wstrb   <=  w_hold_strb;
            end

            //--------------------------------------------------------------
            //Launch a staged internal MMIO read request
            //--------------------------------------------------------------
            if(launch_read_req)
            begin
                req_pending_valid   <=  1'b1;
                req_pending_write   <=  1'b0;
                req_pending_addr    <=  ar_hold_addr;
                req_pending_wdata   <=  '0;
                req_pending_wstrb   <=  '0;
            end

            //--------------------------------------------------------------
            //Internal MMIO request accepted by i2c_regs.sv
            //
            //At this point:
            // - clear the staged request
            // - mark MMIO busy until rsp_valid is returned
            // - release the corresponding AXI holding register
            //-------------------------------------------------------------
            if(req_fire)
            begin
                req_pending_valid   <=  1'b0;
                mmio_busy           <=  1'b1;
                mmio_active_write   <=  req_pending_write;

                if(req_pending_write)
                begin
                    aw_hold_valid   <=  1'b0;
                    w_hold_valid    <=  1'b0;
                end
                else
                begin
                    ar_hold_valid   <=  1'b0;
                end
            end

            //--------------------------------------------------------------
            //Internal MMIO response accpeted from i2c_regs.sv
            //
            //Map internal error response into AXI response encoding.
            //--------------------------------------------------------------
            if(rsp_fire)
            begin
                mmio_busy   <=  1'b0;

                if(mmio_active_write)
                begin
                    s_axil_bvalid   <=  1'b1;
                    s_axil_bresp    <=  rsp_err ?   AXI_RESP_SLVERR :   AXI_RESP_OKAY;
                end
                else
                begin
                    s_axil_rvalid   <=  1'b1;
                    s_axil_rresp    <=  rsp_err ?   AXI_RESP_SLVERR :   AXI_RESP_OKAY;
                    s_axil_rdata    <=  rsp_rdata;
                end
            end

            //--------------------------------------------------------------
            //AXI write response completed
            //-------------------------------------------------------------
            if(b_fire)
            begin
                s_axil_bvalid   <=  1'b0;
            end

            //--------------------------------------------------------------
            //AXI read response completed
            //--------------------------------------------------------------
            if(r_fire)
            begin
                s_axil_rvalid   <=  1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // i2c_regs instance
    //
    // Assumption:
    // i2c_regs uses byte-addressed req_addr values matching the register map:
    //   0x00 STATUS
    //   0x04 DIVISOR
    //   0x08 TXDATA
    //   0x0C RXDATA
    //   0x10 CMD
    //--------------------------------------------------------------------------
    i2c_regs #(
        .ADDR_W      (ADDR_W),
        .DATA_W      (DATA_W),
        .BYTE_W      (BYTE_W),
        .CMD_W       (CMD_W),
        .DIVISOR_W   (DIVISOR_W),
        .MIN_DIVISOR (MIN_DIVISOR))
        u_i2c_regs (
        .clk                (clk),
        .rst_n              (rst_n),

        .req_valid          (req_valid),
        .req_ready          (req_ready),
        .req_write          (req_write),
        .req_addr           (req_addr),
        .req_wdata          (req_wdata),
        .req_wstrb          (req_wstrb),

        .rsp_valid          (rsp_valid),
        .rsp_ready          (rsp_ready),
        .rsp_rdata          (rsp_rdata),
        .rsp_err            (rsp_err),

        .sda_in             (sda_in),
        .sda_out            (sda_out),
        .scl_in             (scl_in),
        .scl_out            (scl_out),
        .master_receiving_o (master_receiving_o)
    );

endmodule