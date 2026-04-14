// pwm_regs_hbridge_ext.sv
//
// H-bridge extension register slice for the PWM family.
//
// -----------------------------------------------------------------------------
// Design intent
// -----------------------------------------------------------------------------
// This block is not a full standalone MMIO peripheral.
// It is a flavor-specific register slice intended to be instantiated inside
// pwm_subsystem_motor.sv alongside pwm_regs_common.sv.
//
// Owns:
//   0x40 DIR_MASK
//   0x44 BRAKE_MASK
//   0x48 COAST_MASK
//
// The block keeps shadow registers for software-visible configuration and active
// registers that update only when apply_commit_i is asserted.
//
// This preserves atomic updates with the common PWM registers.

module pwm_regs_hbridge_ext #(
    parameter int unsigned ADDR_W   = 12,
    parameter int unsigned DATA_W   = 32,
    parameter int unsigned CHANNELS = 4)
    (
    input  logic                    clk,
    input  logic                    rst_n,

    // Decoded MMIO access strobes from parent subsystem
    input  logic                    wr_en,
    input  logic                    rd_en,
    input  logic [ADDR_W-1:0]       addr,
    input  logic [DATA_W-1:0]       wdata,
    input  logic [(DATA_W/8)-1:0]   wstrb,

    // Shared commit pulse from pwm_regs_common
    input  logic                    apply_commit_i,

    // Readback / decode back to parent subsystem
    output logic                    reg_hit_o,
    output logic [DATA_W-1:0]       rdata_o,

    // Active outputs to H-bridge adapter
    output logic [CHANNELS-1:0]     dir_mask_o,
    output logic [CHANNELS-1:0]     brake_mask_o,
    output logic [CHANNELS-1:0]     coast_mask_o);

        initial
        begin
            if (CHANNELS > DATA_W) begin
                $error("pwm_regs_hbridge_ext: CHANNELS (%0d) must be <= DATA_W (%0d)",
                    CHANNELS, DATA_W);
        end
    end

    // -------------------------------------------------------------------------
    // Register map
    // -------------------------------------------------------------------------
    localparam logic [ADDR_W-1:0] REG_DIR_MASK   = 'h40;
    localparam logic [ADDR_W-1:0] REG_BRAKE_MASK = 'h44;
    localparam logic [ADDR_W-1:0] REG_COAST_MASK = 'h48;

    // -------------------------------------------------------------------------
    // Internal state
    // -------------------------------------------------------------------------
    logic [CHANNELS-1:0] dir_shadow;
    logic [CHANNELS-1:0] brake_shadow;
    logic [CHANNELS-1:0] coast_shadow;

    logic [CHANNELS-1:0] dir_active;
    logic [CHANNELS-1:0] brake_active;
    logic [CHANNELS-1:0] coast_active;

    // -------------------------------------------------------------------------
    // Temporary merged write values
    // -------------------------------------------------------------------------
    logic [DATA_W-1:0] dir_merged;
    logic [DATA_W-1:0] brake_merged;
    logic [DATA_W-1:0] coast_merged;

    // -------------------------------------------------------------------------
    // Helper function: byte-write merge for 32-bit regs
    // -------------------------------------------------------------------------
    function automatic logic [DATA_W-1:0] merge_wstrb(
        input logic [DATA_W-1:0]        old_val,
        input logic [DATA_W-1:0]        new_val,
        input logic [(DATA_W/8)-1:0]    strb
    );
        logic [DATA_W-1:0] write_mask;
        begin
            write_mask = {
                {8{strb[3]}},
                {8{strb[2]}},
                {8{strb[1]}},
                {8{strb[0]}}
            };

            return (old_val & ~write_mask) | (new_val & write_mask);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Merged write values
    // -------------------------------------------------------------------------
    always_comb
    begin
        dir_merged = merge_wstrb(
            {{(DATA_W-CHANNELS){1'b0}}, dir_shadow},
            wdata,
            wstrb
        );

        brake_merged = merge_wstrb(
            {{(DATA_W-CHANNELS){1'b0}}, brake_shadow},
            wdata,
            wstrb
        );

        coast_merged = merge_wstrb(
            {{(DATA_W-CHANNELS){1'b0}}, coast_shadow},
            wdata,
            wstrb
        );
    end

    // -------------------------------------------------------------------------
    // Decode / readback
    // -------------------------------------------------------------------------
    always_comb
    begin
        reg_hit_o = 1'b0;
        rdata_o   = '0;

        unique case (addr)
            REG_DIR_MASK:
            begin
                reg_hit_o = 1'b1;
                rdata_o   = '0;
                rdata_o[CHANNELS-1:0] = dir_shadow;
            end

            REG_BRAKE_MASK:
            begin
                reg_hit_o = 1'b1;
                rdata_o   = '0;
                rdata_o[CHANNELS-1:0] = brake_shadow;
            end

            REG_COAST_MASK:
            begin
                reg_hit_o = 1'b1;
                rdata_o   = '0;
                rdata_o[CHANNELS-1:0] = coast_shadow;
            end

            default:
            begin
                reg_hit_o = 1'b0;
                rdata_o   = '0;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
    begin
        if (!rst_n)
        begin
            dir_shadow   <= '0;
            brake_shadow <= '0;
            coast_shadow <= '0;

            dir_active   <= '0;
            brake_active <= '0;
            coast_active <= '0;
        end

        else
        begin
            // Commit shadow -> active on the shared APPLY commit point
            if (apply_commit_i)
            begin
                dir_active   <= dir_shadow;
                brake_active <= brake_shadow;
                coast_active <= coast_shadow;
            end

            // Update shadow registers on writes
            if (wr_en && reg_hit_o)
            begin
                unique case (addr)
                    REG_DIR_MASK:
                    begin
                        dir_shadow <= dir_merged[CHANNELS-1:0];
                    end

                    REG_BRAKE_MASK:
                    begin
                        brake_shadow <= brake_merged[CHANNELS-1:0];
                    end

                    REG_COAST_MASK:
                    begin
                        coast_shadow <= coast_merged[CHANNELS-1:0];
                    end

                    default:
                    begin
                        // no action
                    end
                endcase
            end
        end
    end
endmodule