module  axi_lite_seg7_debug #(
    parameter int ADDR_W        = 12,
    parameter int DATA_W        = 32,
    parameter int NUM_DIGITS    = 6)
    (
    // -------------------------------------------------------------------------
    // AXI4-Lite slave interface
    // -------------------------------------------------------------------------
    input  logic                        clk,
    input  logic                        rst_n,

    input  logic    [ADDR_W-1:0]        s_axi_awaddr,
    input  logic                        s_axi_awvalid,
    output logic                        s_axi_awready,

    input  logic    [DATA_W-1:0]        s_axi_wdata,
    input  logic    [(DATA_W/8)-1:0]    s_axi_wstrb,
    input  logic                        s_axi_wvalid,
    output logic                        s_axi_wready,

    output logic    [1:0]               s_axi_bresp,
    output logic                        s_axi_bvalid,
    input  logic                        s_axi_bready,

    input  logic    [ADDR_W-1:0]        s_axi_araddr,
    input  logic                        s_axi_arvalid,
    output logic                        s_axi_arready,

    output logic    [DATA_W-1:0]        s_axi_rdata,
    output logic    [1:0]               s_axi_rresp,
    output logic                        s_axi_rvalid,
    input  logic                        s_axi_rready,

    // -------------------------------------------------------------------------
    // Live debug source from hardware
    // -------------------------------------------------------------------------
    input   logic   [(NUM_DIGITS*4)-1:0]    live_value_i,

    // -------------------------------------------------------------------------
    // Outputs toward the display core
    // -------------------------------------------------------------------------
    output  logic                           enable_o,
    output  logic   [2:0]                   mode_o,
    output  logic   [NUM_DIGITS-1:0]        dp_n_o,
    output  logic   [NUM_DIGITS-1:0]        blank_o,
    output  logic   [(NUM_DIGITS*4)-1:0]    active_value_o
);

    // -------------------------------------------------------------------------
    // Basic assumptions / intended use
    //
    // 1) This wrapper converts AXI4-Lite transactions into the generic MMIO
    //    request/response interface used by seg7_debug_regs.
    //
    // 2) Only one MMIO transaction is issued at a time.
    //
    // 3) AW, W, and AR channels each have a small one-entry holding register.
    //    That makes the wrapper easier to understand and lets AXI AW/W arrive
    //    independently.
    //
    // 4) Write requests have priority over reads when both are pending.
    //
    // 5) This design assumes NUM_DIGITS*4 <= DATA_W, since the current display
    //    value is returned in a DATA_W-wide read register.
    // -------------------------------------------------------------------------

    localparam  logic   [1:0]   AXI_RESP_OKAY   =   2'b00;
    localparam  logic   [1:0]   AXI_RESP_SLVERR =   2'b10;

    // -------------------------------------------------------------------------
    // FSM definition
    //
    // ST_IDLE            : collect AW/W/AR requests into one-entry holding regs
    // ST_WRITE_REQ       : present a write request to seg7_debug_regs
    // ST_WRITE_WAIT_RSP  : wait for MMIO write response
    // ST_WRITE_B         : return AXI BVALID/BRESP
    // ST_READ_REQ        : present a read request to seg7_debug_regs
    // ST_READ_WAIT_RSP   : wait for MMIO read response
    // ST_READ_R          : return AXI RVALID/RRESP/RDATA
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE             = 3'd0,
        ST_WRITE_REQ        = 3'd1,
        ST_WRITE_WAIT_RSP   = 3'd2,
        ST_WRITE_B          = 3'd3,
        ST_READ_REQ         = 3'd4,
        ST_READ_WAIT_RSP    = 3'd5,
        ST_READ_R           = 3'd6
    } state_t;

    state_t state_reg;
    state_t state_next;

    // -------------------------------------------------------------------------
    // AXI holding registers
    // -------------------------------------------------------------------------
    logic                   aw_hold_valid_reg;
    logic                   aw_hold_valid_next;
    logic [ADDR_W-1:0]      awaddr_hold_reg;
    logic [ADDR_W-1:0]      awaddr_hold_next;

    logic                   w_hold_valid_reg;
    logic                   w_hold_valid_next;
    logic [DATA_W-1:0]      wdata_hold_reg;
    logic [DATA_W-1:0]      wdata_hold_next;
    logic [(DATA_W/8)-1:0]  wstrb_hold_reg;
    logic [(DATA_W/8)-1:0]  wstrb_hold_next;

    logic                   ar_hold_valid_reg;
    logic                   ar_hold_valid_next;
    logic [ADDR_W-1:0]      araddr_hold_reg;
    logic [ADDR_W-1:0]      araddr_hold_next;

    // -------------------------------------------------------------------------
    // AXI response holding registers
    // -------------------------------------------------------------------------
    logic [1:0]             bresp_reg;
    logic [1:0]             bresp_next;

    logic [DATA_W-1:0]      rdata_reg;
    logic [DATA_W-1:0]      rdata_next;
    logic [1:0]             rresp_reg;
    logic [1:0]             rresp_next;

    // -------------------------------------------------------------------------
    // Internal handshakes
    // -------------------------------------------------------------------------
    logic   aw_fire;
    logic   w_fire;
    logic   b_fire;
    logic   ar_fire;
    logic   r_fire;

    // -------------------------------------------------------------------------
    // Internal MMIO connection to seg7_debug_regs
    // -------------------------------------------------------------------------
    logic                   mmio_req_valid;
    logic                   mmio_req_ready;
    logic                   mmio_req_write;
    logic [ADDR_W-1:0]      mmio_req_addr;
    logic [DATA_W-1:0]      mmio_req_wdata;
    logic [(DATA_W/8)-1:0]  mmio_req_wstrb;

    logic                   mmio_rsp_valid;
    logic                   mmio_rsp_ready;
    logic [DATA_W-1:0]      mmio_rsp_rdata;
    logic                   mmio_rsp_err;

    logic                   mmio_req_fire;
    logic                   mmio_rsp_fire;

    // -------------------------------------------------------------------------
    // Instantiate the generic register block
    // -------------------------------------------------------------------------
    seg7_debug_regs #(
        .ADDR_W     (ADDR_W),
        .DATA_W     (DATA_W),
        .NUM_DIGITS (NUM_DIGITS))
        u_seg7_debug_regs (
        .clk_i          (clk),
        .rst_ni         (rst_n),

        .req_valid_i    (mmio_req_valid),
        .req_ready_o    (mmio_req_ready),
        .req_write_i    (mmio_req_write),
        .req_addr_i     (mmio_req_addr),
        .req_wdata_i    (mmio_req_wdata),
        .req_wstrb_i    (mmio_req_wstrb),

        .rsp_valid_o    (mmio_rsp_valid),
        .rsp_ready_i    (mmio_rsp_ready),
        .rsp_rdata_o    (mmio_rsp_rdata),
        .rsp_err_o      (mmio_rsp_err),

        .live_value_i   (live_value_i),

        .enable_o       (enable_o),
        .mode_o         (mode_o),
        .dp_n_o         (dp_n_o),
        .blank_o        (blank_o),
        .active_value_o (active_value_o)
    );

    // -------------------------------------------------------------------------
    // Handshake wires
    // -------------------------------------------------------------------------
    always_comb 
    begin
        aw_fire      = s_axi_awvalid && s_axi_awready;
        w_fire       = s_axi_wvalid  && s_axi_wready;
        b_fire       = s_axi_bvalid  && s_axi_bready;
        ar_fire      = s_axi_arvalid && s_axi_arready;
        r_fire       = s_axi_rvalid  && s_axi_rready;

        mmio_req_fire = mmio_req_valid && mmio_req_ready;
        mmio_rsp_fire = mmio_rsp_valid && mmio_rsp_ready;
    end

    // -------------------------------------------------------------------------
    // AXI ready generation
    //
    // Only accept new channel payloads while idle. Each channel has a one-entry
    // holding register, so READY stays high only if that holding register is free.
    // -------------------------------------------------------------------------
    always_comb
    begin
        s_axi_awready = 1'b0;
        s_axi_wready  = 1'b0;
        s_axi_arready = 1'b0;

        if(state_reg == ST_IDLE) begin
            s_axi_awready = !aw_hold_valid_reg;
            s_axi_wready  = !w_hold_valid_reg;
            s_axi_arready = !ar_hold_valid_reg;
        end
    end

    // -------------------------------------------------------------------------
    // AXI response outputs
    // -------------------------------------------------------------------------
    always_comb
    begin
        s_axi_bvalid = (state_reg == ST_WRITE_B);
        s_axi_bresp  = bresp_reg;

        s_axi_rvalid = (state_reg == ST_READ_R);
        s_axi_rresp  = rresp_reg;
        s_axi_rdata  = rdata_reg;
    end

    // -------------------------------------------------------------------------
    // MMIO request decode from FSM state
    // -------------------------------------------------------------------------
    always_comb
    begin
        mmio_req_valid = 1'b0;
        mmio_req_write = 1'b0;
        mmio_req_addr  = '0;
        mmio_req_wdata = '0;
        mmio_req_wstrb = '0;
        mmio_rsp_ready = 1'b0;

        case (state_reg)
            ST_WRITE_REQ:
            begin
                mmio_req_valid = 1'b1;
                mmio_req_write = 1'b1;
                mmio_req_addr  = awaddr_hold_reg;
                mmio_req_wdata = wdata_hold_reg;
                mmio_req_wstrb = wstrb_hold_reg;
            end

            ST_WRITE_WAIT_RSP:
            begin
                mmio_rsp_ready = 1'b1;
            end

            ST_READ_REQ:
            begin
                mmio_req_valid = 1'b1;
                mmio_req_write = 1'b0;
                mmio_req_addr  = araddr_hold_reg;
                mmio_req_wdata = '0;
                mmio_req_wstrb = '0;
            end

            ST_READ_WAIT_RSP:
            begin
                mmio_rsp_ready = 1'b1;
            end

            default:
            begin
                // no MMIO activity
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Holding-register next-state logic
    //
    // 1) Capture AW/W/AR payloads when their AXI handshakes fire.
    // 2) Clear AW/W after the write MMIO request is accepted.
    // 3) Clear AR after the read MMIO request is accepted.
    // -------------------------------------------------------------------------
    always_comb
    begin
        aw_hold_valid_next = aw_hold_valid_reg;
        awaddr_hold_next   = awaddr_hold_reg;

        w_hold_valid_next  = w_hold_valid_reg;
        wdata_hold_next    = wdata_hold_reg;
        wstrb_hold_next    = wstrb_hold_reg;

        ar_hold_valid_next = ar_hold_valid_reg;
        araddr_hold_next   = araddr_hold_reg;

        // Capture AXI write address channel
        if(aw_fire)
        begin
            aw_hold_valid_next = 1'b1;
            awaddr_hold_next   = s_axi_awaddr;
        end

        // Capture AXI write data channel
        if(w_fire)
        begin
            w_hold_valid_next = 1'b1;
            wdata_hold_next   = s_axi_wdata;
            wstrb_hold_next   = s_axi_wstrb;
        end

        // Capture AXI read address channel
        if(ar_fire)
        begin
            ar_hold_valid_next = 1'b1;
            araddr_hold_next   = s_axi_araddr;
        end

        // Once the MMIO write request is accepted, release AW/W holds
        if((state_reg == ST_WRITE_REQ) && mmio_req_fire)
        begin
            aw_hold_valid_next = 1'b0;
            w_hold_valid_next  = 1'b0;
        end

        // Once the MMIO read request is accepted, release AR hold
        if((state_reg == ST_READ_REQ) && mmio_req_fire)
        begin
            ar_hold_valid_next = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // AXI response register next-state logic
    //
    // Capture MMIO response information into AXI-facing registers. Then the FSM
    // presents that information later on the AXI B or R channel.
    // -------------------------------------------------------------------------
    always_comb begin
        bresp_next = bresp_reg;
        rdata_next = rdata_reg;
        rresp_next = rresp_reg;

        // Write completion: only need BRESP
        if((state_reg == ST_WRITE_WAIT_RSP) && mmio_rsp_fire)
        begin
            bresp_next = mmio_rsp_err ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
        end

        // Read completion: need both RDATA and RRESP
        if((state_reg == ST_READ_WAIT_RSP) && mmio_rsp_fire)
        begin
            rdata_next = mmio_rsp_rdata;
            rresp_next = mmio_rsp_err ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
        end
    end

    // -------------------------------------------------------------------------
    // FSM next-state logic
    //
    // Write has priority over read if both are pending while idle.
    // -------------------------------------------------------------------------
    always_comb
    begin
        state_next = state_reg;

        case (state_reg)
            ST_IDLE:
            begin
                if(aw_hold_valid_reg && w_hold_valid_reg)
                begin
                    state_next = ST_WRITE_REQ;
                end
                else if(ar_hold_valid_reg)
                begin
                    state_next = ST_READ_REQ;
                end
            end

            ST_WRITE_REQ:
            begin
                if(mmio_req_fire)
                begin
                    state_next = ST_WRITE_WAIT_RSP;
                end
            end

            ST_WRITE_WAIT_RSP:
            begin
                if(mmio_rsp_fire)
                begin
                    state_next = ST_WRITE_B;
                end
            end

            ST_WRITE_B:
            begin
                if(b_fire)
                begin
                    state_next = ST_IDLE;
                end
            end

            ST_READ_REQ:
            begin
                if(mmio_req_fire)
                begin
                    state_next = ST_READ_WAIT_RSP;
                end
            end

            ST_READ_WAIT_RSP:
            begin
                if(mmio_rsp_fire)
                begin
                    state_next = ST_READ_R;
                end
            end

            ST_READ_R:
            begin
                if(r_fire)
                begin
                    state_next = ST_IDLE;
                end
            end

            default:
            begin
                state_next = ST_IDLE;
            end
        endcase
    end

    // =========================================================================
    // Sequential logic
    // =========================================================================

    // -------------------------------------------------------------------------
    // FSM state register
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn)
    begin
        if(!s_axi_aresetn)
        begin
            state_reg <= ST_IDLE;
        end
        else
        begin
            state_reg <= state_next;
        end
    end

    // -------------------------------------------------------------------------
    // AW holding registers
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn)
    begin
        if(!s_axi_aresetn)
        begin
            aw_hold_valid_reg <= 1'b0;
            awaddr_hold_reg   <= '0;
        end
        else
        begin
            aw_hold_valid_reg <= aw_hold_valid_next;
            awaddr_hold_reg   <= awaddr_hold_next;
        end
    end

    // -------------------------------------------------------------------------
    // W holding registers
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn)
    begin
        if(!s_axi_aresetn)
        begin
            w_hold_valid_reg <= 1'b0;
            wdata_hold_reg   <= '0;
            wstrb_hold_reg   <= '0;
        end
        else
        begin
            w_hold_valid_reg <= w_hold_valid_next;
            wdata_hold_reg   <= wdata_hold_next;
            wstrb_hold_reg   <= wstrb_hold_next;
        end
    end

    // -------------------------------------------------------------------------
    // AR holding registers
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn)
    begin
        if(!s_axi_aresetn)
        begin
            ar_hold_valid_reg <= 1'b0;
            araddr_hold_reg   <= '0;
        end
        else
        begin
            ar_hold_valid_reg <= ar_hold_valid_next;
            araddr_hold_reg   <= araddr_hold_next;
        end
    end

    // -------------------------------------------------------------------------
    // Write-response registers
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn)
    begin
        if(!s_axi_aresetn)
        begin
            bresp_reg <= AXI_RESP_OKAY;
        end
        else
        begin
            bresp_reg <= bresp_next;
        end
    end

    // -------------------------------------------------------------------------
    // Read-response registers
    // -------------------------------------------------------------------------
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn)
    begin
        if(!s_axi_aresetn)
        begin
            rdata_reg <= '0;
            rresp_reg <= AXI_RESP_OKAY;
        end
        else
        begin
            rdata_reg <= rdata_next;
            rresp_reg <= rresp_next;
        end
    end

endmodule