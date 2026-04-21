//seg7_debug_regs.sv
module  seg7_debug_regs #(
    parameter   int ADDR_W      =   12,
    parameter   int DATA_W      =   32,
    parameter   int SEV_SEG_W   =   6)
    (
    input   logic               clk,
    input   logic               rst_n,

    //Generic   MMIO request/response
    input   logic                       req_valid_i,
    output  logic                       req_ready_o,
    input   logic                       req_write_i,
    input   logic   [ADDR_W-1:0]        req_addr_i,
    input   logic   [DATA_W-1:0]        req_wdata_i,
    input   logic   [(DATA_W/8)-1:0]    req_wstrb_i,

    output  logic                       rsp_valid_o,
    input   logic                       rsp_ready_i,
    output  logic   [DATA_W-1:0]        rsp_rdata_o,
    output  logic                       rsp_err_o,

    //Live debug source from hardware
    input   logic   [(SEV_SEG_W*4)-1:0]              live_value_i,

    //Outputs to display core
    output  logic                       enable_o,
    output  logic   [2:0]               mode_o,
    output  logic   [5:0]               dp_n_o,
    output  logic   [5:0]               blank_o,
    output  logic   [(SEV_SEG_W*4)-1:0]              active_value_o);

    //----------------------------------------------------------
    //Register map
    //----------------------------------------------------------
    localparam  logic   [7:0]   REG_CTRL            =   8'h00;
    localparam  logic   [7:0]   REG_SW_VALUE        =   8'h04;
    localparam  logic   [7:0]   REG_DP_N            =   8'h08;
    localparam  logic   [7:0]   REG_BLANK           =   8'h0C;
    localparam  logic   [7:0]   REG_LIVE_VALUE      =   8'h10;
    localparam  logic   [7:0]   REG_FROZEN_VALUE    =   8'h14;
    localparam  logic   [7:0]   REG_ACTIVE_VALUE    =   8'h18;
    localparam  logic   [7:0]   REG_STATUS          =   8'h1C;

    //-----------------------------------------------------------
    //CTRL Register bit definitions
    //-----------------------------------------------------------
    localparam  int CTRL_EN_BIT             =   0;
    localparam  int CTRL_MODE_LSB           =   1;
    localparam  int CTRL_MODE_MSB           =   3;
    localparam  int CTRL_SRC_SEL_BIT        =   4;
    localparam  int CTRL_FREEZE_BIT         =   5;
    localparam  int CTRL_SNAPSHOT_BIT       =   6;  //W1P, not stored

    //-----------------------------------------------------------
    //Registered state
    //-----------------------------------------------------------
    logic   [31:0]  ctrl_reg;
    logic   [31:0]  sw_value_reg;
    logic   [31:0]  dp_n_reg;
    logic   [31:0]  blank_reg;
    logic   [31:0]  frozen_value_reg;

    logic           rsp_valid_reg;
    logic   [31:0]  rsp_rdata_reg;
    logic           rsp_err_reg;

    //------------------------------------------------------------
    //Next-state signals
    //------------------------------------------------------------
    logic   [31:0]  ctrl_next;
    logic   [31:0]  sw_value_next;
    logic   [31:0]  dp_n_next;
    logic   [31:0]  blank_next;
    logic   [31:0]  frozen_value_next;

    logic           rsp_valid_next;
    logic   [31:0]  rsp_rdata_next;
    logic           rsp_err_next;

    //-------------------------------------------------------------
    //Internal control
    //-------------------------------------------------------------
    

    logic           snapshot_pulse;
    logic           freeze_rise;
    
    //-------------------------------------------------------------
    //Write-strobe function
    //-------------------------------------------------------------
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


    //---------------------------------------------------------------
    //Request/response handshake
    //Only accept a new request whe we are not holding a pending response,
    //or when that response is being accepted int he same cycle
    //---------------------------------------------------------------
    logic           req_fire;
    logic           wr_fire;
    logic           rsp_fire;

    assign  rsp_fire    =   rsp_valid_o &&   rsp_ready_i;
    assign  req_fire    =   req_valid_i &&   req_ready_o;
    assign  wr_fire     =   req_fire    &&   req_write_i;

    assign  req_ready_o =   ~rsp_valid_reg  ||   rsp_ready_i;
    assign  rsp_valid_o =   rsp_valid_reg;
    assign  rsp_rdata_o =   rsp_rdata_reg;
    assign  rsp_err_o   =   rsp_err_reg;


    //----------------------------------------------------------------
    //Temporary merged valudes and command launch payload
    //----------------------------------------------------------------
    logic   [DATA_W-1:0]    status_rdata;


    logic   [DATA_W-1:0]    ctrl_merged;
    logic   [DATA_W-1:0]    sw_value_merged;
    logic   [DATA_W-1:0]    dp_n_merged;
    logic   [DATA_W-1:0]    blank_merged;

    assign  ctrl_merged     =   merge_wstrb(ctrl_reg,       req_wdata_i,  req_wstrb_i);  
    assign  sw_value_merged =   merge_wstrb(sw_value_reg,   req_wdata_i,  req_wstrb_i);
    assign  dp_n_merged     =   merge_wstrb(dp_n_reg,       req_wdata_i,  req_wstrb_i);
    assign  blank_merged    =   merge_wstrb(blank_reg,      req_wdata_i,  req_wstrb_i);

    //----------------------------------------------------------------
    //status assembly
    //----------------------------------------------------------------
    always_comb
    begin
        status_rdata                                =   '0;
        status_rdata[CTRL_EN_BIT]                   =   ctrl_reg[CTRL_EN_BIT];
        status_rdata[CTRL_MODE_MSB:CTRL_MODE_LSB]   =   ctrl_reg[CTRL_MODE_MSB:CTRL_MODE_LSB];
        status_rdata[CTRL_SRC_SEL_BIT]              =   ctrl_reg[CTRL_SRC_SEL_BIT];
        status_rdata[CTRL_FREEZE_BIT]               =   ctrl_reg[CTRL_FREEZE_BIT];
        status_rdata[CTRL_SNAPSHOT_BIT]             =   ctrl_reg[CTRL_SNAPSHOT_BIT];
    end

    //--------------------------------------------------------------------
    //snapshot_pulse and freeze_rise circuitry
    //--------------------------------------------------------------------
    always_comb
    begin
        frozen_value_next   =   frozen_value_reg;

        snapshot_pulse  =   req_wstrb_i[0]  &&  req_wdata_i[CTRL_SNAPSHOT_BIT];
        //Detect FREEZE rising edge so we can capture live_value
        freeze_rise =   (~ctrl_reg[CTRL_FREEZE_BIT]) &   ctrl_next[CTRL_FREEZE_BIT];

        //Capture the live value either on SNAPSHOT pulse or
        //when FREEZE is newly asserted.
        if(snapshot_pulse   ||  freeze_rise)
        begin
            frozen_value_next[(SEV_SEG_W*4):0]  =   live_value_i;
        end
    end


    //--------------------------------------------------------------------
    //rsp_data answer after Write request
    //--------------------------------------------------------------------
    always_comb
    begin
        //Default
        ctrl_next           =   ctrl_reg;
        sw_value_next       =   sw_value_reg;
        dp_n_next           =   dp_n_reg;
        blank_next          =   blank_reg;
        

        if(req_write_i)
        begin
            unique  case    (req_addr_i[7:0])
            REG_CTRL:
                begin
                    ctrl_next   =   ctrl_merged;

                end

                REG_SW_VALUE:
                begin
                    sw_value_next   =   sw_value_merged;
                end

                REG_DP_N:
                begin
                    dp_n_next   =   dp_n_merged;
                end

                REG_BLANK:
                begin
                    blank_next  =   blank_merged;

                default:
                begin
                    rsp_err_next    =   1'b1;
                end
            endcase
        end

    //--------------------------------------------------------------------
    //rsp_data answer after read request
    //--------------------------------------------------------------------
    always_comb
    begin
        rsp_rdata_next  =   rsp_rdata_reg;
        if(!req_write_i)
        begin
            unique  case    (req_addr_i[7:0])
                REG_CTRL:
                begin
                    rsp_rdata_next  =   ctrl_reg;
                end

                REG_SW_VALUE:
                begin
                    rsp_rdata_next  =   sw_value_reg;
                end

                REG_DP_N:
                begin
                    rsp_rdata_next  =   dp_n_reg;
                end

                REG_BLANK:
                begin
                    rsp_rdata_next  =   blank_reg;
                end

                REG_LIVE_VALUE:
                begin
                    rsp_rdata_next  =   {{DATA_W-(SEV_SEG_W*4){1'b0}},  live_value_i};
                end

                REG_FROZEN_VALUE:
                begin
                    rsp_rdata_next  =   frozen_value_reg;
                end

                REG_ACTIVE_VALUE:
                begin
                    rsp_rdata_next  =   {{DATA_W-(SEV_SEG_W*4){1'b0}},  live_value_o};
                end

                REG_STATUS:
                begin
                    rsp_rdata_next  =   status_rdata;
                end

                default:
                begin
                    rsp_rdata_next  =   '0;
                    rsp_err_next    =   1'b1;
                end
            endcase
        end
    end


    //----------------------------------------------------------------
    //response MMIO control
    //----------------------------------------------------------------
    always_comb
    begin
        rsp_valid_next      =   rsp_valid_reg;
        rsp_rdata_next      =   rsp_rdata_reg;
        rsp_err_next        =   rsp_err_reg;

        //Clear response valid once the response is accepted.
        if(rsp_fire)
        begin
            rsp_valid_next  =   1'b0;
        end

        if(req_fire)
        begin
            rsp_valid_next  =   1'b1;
            rsp_rdata_next  =   '0;
            rsp_err_next    =   1'b0;
        end
    end

    //-------------------------------------------------------------------
    //Response Channel
    //-------------------------------------------------------------------
    //One response per accepted request
    //Response is held until rsp_ready
    always_ff   @(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
        begin
            rsp_valid_reg   <=  1'b0;
            rsp_rdata_reg   <=  '0;
            rsp_err_reg     <=  1'b0;
        end
        else
        begin
            if(rsp_fire)
                rsp_valid_reg   <=  1'b0;

            if(req_fire)
            begin
                rsp_valid_reg   <=  1'b1;
                rsp_rdata_reg   <=  rdata_next;
                rsp_err_reg     <=  err_next;
            end
        end
    end

    //----------------------------------------------------------------
    //Register update
    //----------------------------------------------------------------
    always_ff   @(posedge   clk or  negedge rst_n)
    begin
        if(!rst_n)
        begin
            ctrl_reg            <=  '0;
            sw_value_reg        <=  '0;
            dp_n_reg            <=  '0;
            blank_reg           <=  '0;
            frozen_value_reg    <=  '0;
        end

        else
        begin
            ctrl_reg            <=  ctrl_next;
            sw_value_reg        <=  sw_value_next;
            dp_n_reg            <=  dp_n_next;
            blank_reg           <=  blank_next;
            frozen_value_reg    <=  frozen_value_next;
        end
    end

    //----------------------------------------------------------------
    //Outputs to the display core
    //----------------------------------------------------------------
    assign  enable_o    =   ctrl_reg[CTRL_EN_BIT];
    assign  mode_o      =   ctrl_reg[CTRL_MODE_MSB:CTRL_MODE_LSB];
    assign  dp_n_o      =   dp_n_reg[5:0];
    assign  blank_o     =   blank_reg[5:0];

    //Source selection:
    //  -SRC_SEL=1  -> software-written 24-bit value
    //  -SRC_SEL=0  & FREEZE=1 -> frozen snapshot of live value
    //  -SRC_SEL=0  & FREEZE=0 -> direct live value
    assign  active_value_o  =   ctrl_reg[4] ?   sw_value_reg[(SEV_SEG_W*4)-1:0]     :
                                ctrl_reg[5] ?   frozen_value_reg[(SEV_SEG_W*4)-1:0] :
                                live_value_i;