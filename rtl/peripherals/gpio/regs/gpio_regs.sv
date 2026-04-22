module gpio_regs #(
    parameter int ADDR_W = 12,
    parameter int DATA_W = 32,
    parameter int GPIO_W = 32)
    (
    input  logic                        clk,
    input  logic                        rst_n,

    // Generic MMIO request/response
    input  logic                        req_valid,
    output logic                        req_ready,
    input  logic                        req_write,
    input  logic    [ADDR_W-1:0]        req_addr,
    input  logic    [DATA_W-1:0]        req_wdata,
    input  logic    [(DATA_W/8)-1:0]    req_wstrb,

    output logic                        rsp_valid,
    input  logic                        rsp_ready,
    output logic    [DATA_W-1:0]        rsp_rdata,
    output logic                        rsp_err,

    // GPIO fabric side
    input  logic    [GPIO_W-1:0]        gpio_in_i,
    output logic    [GPIO_W-1:0]        gpio_out_o,
    output logic    [GPIO_W-1:0]        gpio_oe_o,
    output logic                        irq_o
);

    localparam logic [ADDR_W-1:0] REG_DATA_IN   = 12'h000;
    localparam logic [ADDR_W-1:0] REG_DATA_OUT  = 12'h004;
    localparam logic [ADDR_W-1:0] REG_DATA_OE   = 12'h008;
    localparam logic [ADDR_W-1:0] REG_RISE_IP   = 12'h00C;
    localparam logic [ADDR_W-1:0] REG_FALL_IP   = 12'h010;
    localparam logic [ADDR_W-1:0] REG_IRQ_MASK  = 12'h014;
    localparam logic [ADDR_W-1:0] REG_INPUT_POL = 12'h018;
    localparam logic [ADDR_W-1:0] REG_DATA_RAW  = 12'h01C;

    //-------------------------------------------------------------
    //Write-strobe function
    //-------------------------------------------------------------
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
        
        return  (old_val    &   ~write_mask)    |   (new_val & write_mask);
    end
    endfunction

    function automatic logic [DATA_W-1:0] pack_gpio(
        input logic [GPIO_W-1:0] vec
    );
        logic [DATA_W-1:0] result;
        begin
            result = '0;
            result[GPIO_W-1:0] = vec;
            return result;
        end
    endfunction

    logic [GPIO_W-1:0] gpio_sync1_reg, gpio_sync1_next;
    logic [GPIO_W-1:0] gpio_sync2_reg, gpio_sync2_next;
    logic [GPIO_W-1:0] gpio_prev_reg,  gpio_prev_next;

    logic [DATA_W-1:0] data_out_reg,   data_out_next;
    logic [DATA_W-1:0] data_oe_reg,    data_oe_next;
    logic [DATA_W-1:0] rise_irq_pending_reg,    rise_irq_pending_next;
    logic [DATA_W-1:0] fall_irq_pending_reg,    fall_irq_pending_next;
    logic [DATA_W-1:0] irq_mask_reg,   irq_mask_next;
    logic [DATA_W-1:0] input_pol_reg,  input_pol_next;

    logic              rsp_valid_reg,  rsp_valid_next;
    logic [DATA_W-1:0] rsp_rdata_reg,  rsp_rdata_next;
    logic              rsp_err_reg,    rsp_err_next;

    logic [GPIO_W-1:0] gpio_in_norm;
    logic [GPIO_W-1:0] rise_evt;
    logic [GPIO_W-1:0] fall_evt;

    logic              rsp_fire;
    logic              req_fire;

    logic [DATA_W-1:0] read_data;
    logic              read_err;
    logic              write_err;

    logic              wr_data_out_hit;
    logic              wr_data_oe_hit;
    logic              wr_rise_irq_pending_hit;
    logic              wr_fall_irq_pending_hit;
    logic              wr_irq_mask_hit;
    logic              wr_input_pol_hit;

    logic [DATA_W-1:0] req_wmask;
    logic [DATA_W-1:0] input_pol_write_data;
    logic [GPIO_W-1:0] input_pol_write_gpio;

    assign gpio_in_norm     = gpio_sync2_reg ^ input_pol_reg[GPIO_W-1:0];
    assign rise_evt         =  gpio_in_norm & ~gpio_prev_reg;
    assign fall_evt         = ~gpio_in_norm &  gpio_prev_reg;

    assign req_ready                = ~rsp_valid_reg | rsp_ready;
    assign rsp_fire                 = rsp_valid_reg & rsp_ready;
    assign req_fire                 = req_valid & req_ready;

    assign wr_data_out_hit          = req_fire & req_write & (req_addr == REG_DATA_OUT);
    assign wr_data_oe_hit           = req_fire & req_write & (req_addr == REG_DATA_OE);
    assign wr_rise_irq_pending_hit  = req_fire & req_write & (req_addr == REG_RISE_IP);
    assign wr_fall_irq_pending_hit  = req_fire & req_write & (req_addr == REG_FALL_IP);
    assign wr_irq_mask_hit          = req_fire & req_write & (req_addr == REG_IRQ_MASK);
    assign wr_input_pol_hit         = req_fire & req_write & (req_addr == REG_INPUT_POL);

    assign req_wmask            = merge_wstrb('0, req_wdata, req_wstrb);
    assign input_pol_write_data = merge_wstrb(input_pol_reg, req_wdata, req_wstrb);
    assign input_pol_write_gpio = input_pol_write_data[GPIO_W-1:0];

    always_comb
    begin
        read_data = '0;
        read_err  = 1'b0;

        unique case (req_addr)
            REG_DATA_IN:   read_data = pack_gpio(gpio_in_norm);
            REG_DATA_OUT:  read_data = data_out_reg;
            REG_DATA_OE:   read_data = data_oe_reg;
            REG_RISE_IP:   read_data = rise_irq_pending_reg;
            REG_FALL_IP:   read_data = fall_irq_pending_reg;
            REG_IRQ_MASK:  read_data = irq_mask_reg;
            REG_INPUT_POL: read_data = input_pol_reg;
            REG_DATA_RAW:  read_data = pack_gpio(gpio_sync2_reg);
            default: begin
                read_data = '0;
                read_err  = 1'b1;
            end
        endcase
    end

    always_comb
    begin
        write_err = 1'b0;

        if (req_write)
        begin
            unique case (req_addr)
                REG_DATA_OUT,
                REG_DATA_OE,
                REG_RISE_IP,
                REG_FALL_IP,
                REG_IRQ_MASK,
                REG_INPUT_POL: write_err = 1'b0;
                default:       write_err = 1'b1;
            endcase
        end
    end

    always_comb
    begin
        gpio_sync1_next = gpio_sync1_reg;
        gpio_sync2_next = gpio_sync2_reg;
        gpio_prev_next  = gpio_prev_reg;

        data_out_next   = data_out_reg;
        data_oe_next    = data_oe_reg;
        rise_irq_pending_next    = rise_irq_pending_reg;
        fall_irq_pending_next    = fall_irq_pending_reg;
        irq_mask_next   = irq_mask_reg;
        input_pol_next  = input_pol_reg;

        rsp_valid_next  = rsp_valid_reg;
        rsp_rdata_next  = rsp_rdata_reg;
        rsp_err_next    = rsp_err_reg;

        // 2-FF input synchronizer
        gpio_sync1_next = gpio_in_i;
        gpio_sync2_next = gpio_sync1_reg;

        // Default edge tracking behavior
        rise_irq_pending_next = rise_irq_pending_reg | pack_gpio(rise_evt);
        fall_irq_pending_next = fall_irq_pending_reg | pack_gpio(fall_evt);
        gpio_prev_next = gpio_in_norm;

        // Suppress false edges when changing input polarity
        if (wr_input_pol_hit)
        begin
            input_pol_next          = input_pol_write_data;
            rise_irq_pending_next   = rise_irq_pending_reg;
            fall_irq_pending_next   = fall_irq_pending_reg;
            gpio_prev_next          = gpio_sync2_reg ^ input_pol_write_gpio;
        end

        // RW registers
        if (wr_data_out_hit)
        begin
            data_out_next = merge_wstrb(data_out_reg, req_wdata, req_wstrb);
        end

        if (wr_data_oe_hit)
        begin
            data_oe_next = merge_wstrb(data_oe_reg, req_wdata, req_wstrb);
        end

        if (wr_irq_mask_hit)
        begin
            irq_mask_next = merge_wstrb(irq_mask_reg, req_wdata, req_wstrb);
        end

        // RW1C pending registers
        if (wr_rise_irq_pending_hit)
        begin
            rise_irq_pending_next = rise_irq_pending_next & ~req_wmask;
        end

        if (wr_fall_irq_pending_hit)
        begin
            fall_irq_pending_next = fall_irq_pending_next & ~req_wmask;
        end

        // Response channel
        if (rsp_fire)
        begin
            rsp_valid_next = 1'b0;
        end

        if (req_fire)
        begin
            rsp_valid_next = 1'b1;
            rsp_rdata_next = req_write ? '0 : read_data;
            rsp_err_next   = req_write ? write_err : read_err;
        end
    end

    always_ff @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            gpio_sync1_reg <= '0;
            gpio_sync2_reg <= '0;
            gpio_prev_reg  <= '0;

            data_out_reg   <= '0;
            data_oe_reg    <= '0;
            rise_irq_pending_reg    <= '0;
            fall_irq_pending_reg    <= '0;
            irq_mask_reg   <= '0;
            input_pol_reg  <= '0;

            rsp_valid_reg  <= 1'b0;
            rsp_rdata_reg  <= '0;
            rsp_err_reg    <= 1'b0;
        end
        else
        begin
            gpio_sync1_reg <= gpio_sync1_next;
            gpio_sync2_reg <= gpio_sync2_next;
            gpio_prev_reg  <= gpio_prev_next;

            data_out_reg   <= data_out_next;
            data_oe_reg    <= data_oe_next;
            rise_irq_pending_reg    <= rise_irq_pending_next;
            fall_irq_pending_reg    <= fall_irq_pending_next;
            irq_mask_reg   <= irq_mask_next;
            input_pol_reg  <= input_pol_next;

            rsp_valid_reg  <= rsp_valid_next;
            rsp_rdata_reg  <= rsp_rdata_next;
            rsp_err_reg    <= rsp_err_next;
        end
    end

    assign gpio_out_o = data_out_reg[GPIO_W-1:0];
    assign gpio_oe_o  = data_oe_reg[GPIO_W-1:0];

    assign irq_o      = |(((rise_irq_pending_reg | fall_irq_pending_reg) & irq_mask_reg));

    assign rsp_valid  = rsp_valid_reg;
    assign rsp_rdata  = rsp_rdata_reg;
    assign rsp_err    = rsp_err_reg;

endmodule