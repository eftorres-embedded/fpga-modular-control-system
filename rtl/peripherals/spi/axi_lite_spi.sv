//axi_lite_spi.sv
//-----------------------------------------------------------------------------
//This module wraps the SPI core from:
//https://opencores.org/projects/spi_verilog_interface
//Licensed under LGPL
//-----------------------------------------------------------------------------
//------------------------------------------------------------------------------
//
//AXI4-Lite slave wrapper for spi_regs.sv
//
//Purpose:
// - Present a standard AXI4-Lite slave interface at the top level
// - Bridge AXI4-Lite transactions into the internal generic MMIO interface
// - Instantiate spi_regs.sv without modifying it
//
//Design notes:
// - One internal MMIO request is active at a time
// - AXI write address (AW) and write data (W) are captured independently
// - A write request is issued only after both AW and W have been captured
// - Read requests are issued from AR
// - Writes are given priority over reads when both are pending
// - Response mapping:
//     rsp_err = 0 -> AXI OKAY   (2'b00)
//     rsp_err = 1 -> AXI SLVERR (2'b10)
//
//2 sets of registers are used:
//the *_hold_* set connects to the AXI side, they are pieced that need "assembly"
//the *_pending_* set is an "assembled" MMMIO command.
// the second set helps to reduce messy combinational logic and make it easy to
//track signals
//the second set is needed because it registers: arbitration, assembly and policy
//We might be able to exted the second set into a multi0entry queue for buffering
//------------------------------------------------------------------------------

module axi_lite_spi #(
    parameter int unsigned AXIL_ADDR_W = 12,
    parameter int unsigned DATA_W      = 32
) (
    input  logic                         clk,
    input  logic                         rst_n,

    //--------------------------------------------------------------------------
    //AXI4-Lite slave interface
    //--------------------------------------------------------------------------
    //Write address channel
    input  logic [AXIL_ADDR_W-1:0]       s_axil_awaddr,
    input  logic                         s_axil_awvalid,
    output logic                         s_axil_awready,

    //Write data channel
    input  logic [DATA_W-1:0]            s_axil_wdata,
    input  logic [(DATA_W/8)-1:0]        s_axil_wstrb,
    input  logic                         s_axil_wvalid,
    output logic                         s_axil_wready,

    //Write response channel
    output logic [1:0]                   s_axil_bresp,
    output logic                         s_axil_bvalid,
    input  logic                         s_axil_bready,

    //Read address channel
    input  logic [AXIL_ADDR_W-1:0]       s_axil_araddr,
    input  logic                         s_axil_arvalid,
    output logic                         s_axil_arready,

    //Read data channel
    output logic [DATA_W-1:0]            s_axil_rdata,
    output logic [1:0]                   s_axil_rresp,
    output logic                         s_axil_rvalid,
    input  logic                         s_axil_rready,

    //--------------------------------------------------------------------------
    //SPI top-level signals
    //--------------------------------------------------------------------------
    output logic                         irq,
    output logic                         spi_sclk,
    output logic                         spi_mosi,
    input  logic                         spi_miso,
    output logic                         spi_cs_n
);

    //--------------------------------------------------------------------------
    //Local parameters
    //--------------------------------------------------------------------------
    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    //--------------------------------------------------------------------------
    //One-deep holding registers for AXI channels
    //
    //These decouple the AXI channels from the internal MMIO request channel.
    //AW and W may arrive in different cycles; we capture them independently.
    //ARVALID can arrive  while still holding a write address, etc.
    //--------------------------------------------------------------------------
    logic                      aw_hold_valid;
    logic [AXIL_ADDR_W-1:0]    aw_hold_addr;

    logic                      w_hold_valid;
    logic [DATA_W-1:0]         w_hold_data;
    logic [(DATA_W/8)-1:0]     w_hold_strb;

    logic                      ar_hold_valid;
    logic [AXIL_ADDR_W-1:0]    ar_hold_addr;

    //--------------------------------------------------------------------------
    //AXI handshake aliases
    //--------------------------------------------------------------------------
    logic aw_fire;
    logic w_fire;
    logic ar_fire;
    logic b_fire;
    logic r_fire;
    logic rsp_fire;

    assign aw_fire = s_axil_awvalid && s_axil_awready;
    assign w_fire  = s_axil_wvalid  && s_axil_wready;
    assign ar_fire = s_axil_arvalid && s_axil_arready;
    assign b_fire  = s_axil_bvalid  && s_axil_bready;
    assign r_fire  = s_axil_rvalid  && s_axil_rready;
    assign rsp_fire =   rsp_valid   &&  rsp_ready;

    //--------------------------------------------------------------------------
    //Internal MMIO interface to spi_regs.sv
    //--------------------------------------------------------------------------
    logic                      req_valid;
    logic                      req_ready;
    logic                      req_write;
    logic [AXIL_ADDR_W-1:0]    req_addr;
    logic [DATA_W-1:0]         req_wdata;
    logic [(DATA_W/8)-1:0]     req_wstrb;

    logic                      rsp_valid;
    logic                      rsp_ready;
    logic [DATA_W-1:0]         rsp_rdata;
    logic                      rsp_err;

    //--------------------------------------------------------------------------
    //MMIO request staging
    //
    //req_* is driven from registered staging fields below.
    //This makes the bridge easy to reason about and avoids confusing combinational
    //request generation.
    //--------------------------------------------------------------------------
    logic                      req_pending_valid;
    logic                      req_pending_write;
    logic [AXIL_ADDR_W-1:0]    req_pending_addr;
    logic [DATA_W-1:0]         req_pending_wdata;
    logic [(DATA_W/8)-1:0]     req_pending_wstrb;

    //Tracks the request that has been accepted by spi_regs and is awaiting
    //a response. These are registers
    logic                      mmio_busy;
    logic                      mmio_active_write; //MMIO transaction currently in flight is a write

    //Alias for when a requisition can happen
    logic req_fire;
    assign req_fire = req_valid && req_ready;

    //these staging registers are used to keep code neat and clean
    //they connect to the MMIO side
    assign req_valid = req_pending_valid;
    assign req_write = req_pending_write;
    assign req_addr  = req_pending_addr;
    assign req_wdata = req_pending_wdata;
    assign req_wstrb = req_pending_wstrb;

    //In this simple wrapper, only one MMIO request can happen at a time
    //there is no extra backpressure stage (we don't have to wait for 
    //master to stop being busy)
    //So, as soon as there is a mmio transfer pending, AXI should
    //be able to read it's response right away. 
    assign rsp_ready = mmio_busy;

    //--------------------------------------------------------------------------
    //AXI ready generation
    //
    //One-deep channel buffering:
    // - Accept AW only when AW holding register is empty
    // - Accept W  only when W  holding register is empty
    // - Accept AR only when AR holding register is empty
    //--------------------------------------------------------------------------
    always_comb
    begin
        s_axil_awready = !aw_hold_valid;
        s_axil_wready  = !w_hold_valid;
        s_axil_arready = !ar_hold_valid;
    end

    //--------------------------------------------------------------------------
    //Request issue decisions
    //
    //Writes are prioritized over reads.
    //
    //launch_write_req:
    // Both AW and W have been captured, and no internal transaction is active.
    //
    //launch_read_req:
    // AR has been captured, no write is waiting to launch, and no internal
    // transaction is active.
    //--------------------------------------------------------------------------
    logic launch_write_req;
    logic launch_read_req;

    always_comb
    begin
        launch_write_req = 1'b0;
        launch_read_req  = 1'b0;

        if(!req_pending_valid && !mmio_busy)
        begin
            if(aw_hold_valid && w_hold_valid)
            begin
                launch_write_req = 1'b1;
            end
            else if(ar_hold_valid)
            begin
                launch_read_req = 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    //Sequential control
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            //------------------------------------------------------------------
            //Reset: clear AXI holding regs
            //------------------------------------------------------------------
            aw_hold_valid     <= 1'b0;
            aw_hold_addr      <= '0;

            w_hold_valid      <= 1'b0;
            w_hold_data       <= '0;
            w_hold_strb       <= '0;

            ar_hold_valid     <= 1'b0;
            ar_hold_addr      <= '0;

            //------------------------------------------------------------------
            //Reset: clear MMIO staging / tracking
            //------------------------------------------------------------------
            req_pending_valid <= 1'b0;
            req_pending_write <= 1'b0;
            req_pending_addr  <= '0;
            req_pending_wdata <= '0;
            req_pending_wstrb <= '0;

            mmio_busy         <= 1'b0;
            mmio_active_write <= 1'b0;

            //------------------------------------------------------------------
            //Reset: clear AXI responses
            //------------------------------------------------------------------
            s_axil_bvalid     <= 1'b0;
            s_axil_bresp      <= AXI_RESP_OKAY;

            s_axil_rvalid     <= 1'b0;
            s_axil_rresp      <= AXI_RESP_OKAY;
            s_axil_rdata      <= '0;
        end

        else
        //We manually set the valid to 1 manually, since it's saying that the data/addres
        //we are currently holding is valid. And it signals that data/address has been
        //accepted
        begin
            //------------------------------------------------------------------
            //Capture AXI write address channel
            //------------------------------------------------------------------
            if(aw_fire)
            begin
                aw_hold_valid <= 1'b1;
                aw_hold_addr  <= s_axil_awaddr;
            end

            //------------------------------------------------------------------
            //Capture AXI write data channel
            //------------------------------------------------------------------
            if(w_fire)
            begin
                w_hold_valid <= 1'b1;
                w_hold_data  <= s_axil_wdata;
                w_hold_strb  <= s_axil_wstrb;
            end

            //------------------------------------------------------------------
            //Capture AXI read address channel
            //------------------------------------------------------------------
            if(ar_fire)
            begin
                ar_hold_valid <= 1'b1;
                ar_hold_addr  <= s_axil_araddr;
            end

            //------------------------------------------------------------------
            //Launch a staged internal MMIO write request
            //The whole "writing" packaged coming from AXI master is fully assembled
            //------------------------------------------------------------------
            if(launch_write_req)
            begin
                req_pending_valid <= 1'b1;
                req_pending_write <= 1'b1;
                req_pending_addr  <= aw_hold_addr;
                req_pending_wdata <= w_hold_data;
                req_pending_wstrb <= w_hold_strb;
            end

            //------------------------------------------------------------------
            //Launch a staged internal MMIO read request
            //The whole "reading" package coming from AXI master is fully assembled
            //------------------------------------------------------------------
            if(launch_read_req)
            begin
                req_pending_valid <= 1'b1;
                req_pending_write <= 1'b0;
                req_pending_addr  <= ar_hold_addr;
                req_pending_wdata <= '0;
                req_pending_wstrb <= '0;
            end

            //------------------------------------------------------------------
            //Internal MMIO request accepted by spi_regs.sv
            //
            //At this point:
            // - clear the staged request
            // - mark MMIO busy until rsp_valid is returned
            // - release the corresponding AXI holding register(s)
            //------------------------------------------------------------------
            if(req_fire)
            begin
                req_pending_valid <= 1'b0;
                mmio_busy         <= 1'b1;
                mmio_active_write <= req_pending_write;

                if(req_pending_write)
                begin
                    aw_hold_valid <= 1'b0;
                    w_hold_valid  <= 1'b0;
                end
                else
                begin
                    ar_hold_valid <= 1'b0;
                end
            end

            //------------------------------------------------------------------
            //Internal MMIO response accepted from spi_regs.sv
            //
            //Map internal error response into AXI response encoding.
            //------------------------------------------------------------------
            if(rsp_fire)
            begin
                mmio_busy <= 1'b0;

                if(mmio_active_write)
                begin
                    s_axil_bvalid <= 1'b1;
                    s_axil_bresp  <= rsp_err ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
                end
                else
                begin
                    s_axil_rvalid <= 1'b1;
                    s_axil_rresp  <= rsp_err ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
                    s_axil_rdata  <= rsp_rdata;
                end
            end

            //------------------------------------------------------------------
            //AXI write response completed
            //------------------------------------------------------------------
            if(b_fire)
            begin
                s_axil_bvalid <= 1'b0;
            end

            //------------------------------------------------------------------
            //AXI read response completed
            //------------------------------------------------------------------
            if(r_fire)
            begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    //spi_regs instance
    //
    //Assumption:
    // spi_regs uses byte-addressed req_addr values matching the register map:
    //   0x00 CTRL
    //   0x04 STATUS
    //   0x08 TXDATA
    //   0x0C RXDATA
    //   0x10 IRQ_EN
    //   0x14 IRQ_STATUS
    //--------------------------------------------------------------------------
    spi_regs #(
        .ADDR_W (AXIL_ADDR_W),
        .DATA_W (DATA_W)
    ) u_spi_regs (
        .clk        (clk),
        .rst_n      (rst_n),

        .req_valid  (req_valid),
        .req_ready  (req_ready),
        .req_write  (req_write),
        .req_addr   (req_addr),
        .req_wdata  (req_wdata),
        .req_wstrb  (req_wstrb),

        .rsp_valid  (rsp_valid),
        .rsp_ready  (rsp_ready),
        .rsp_rdata  (rsp_rdata),
        .rsp_err    (rsp_err),

        .irq        (irq),
        .spi_sclk   (spi_sclk),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso),
        .spi_cs_n   (spi_cs_n)
    );

endmodule