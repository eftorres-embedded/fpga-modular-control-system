#include "seg7_debug_regs.h"

#include "io.h"

static uint32_t seg7_read(uint32_t offset)
{
    return IORD_32DIRECT(SEG7_DEBUG_BASE, offset);
}

static void seg7_write(uint32_t offset, uint32_t value)
{
    IOWR_32DIRECT(SEG7_DEBUG_BASE, offset, value);
}

static void seg7_update_ctrl(uint32_t clear_mask, uint32_t set_mask)
{
    uint32_t ctrl = seg7_get_ctrl();
    ctrl &= ~clear_mask;
    ctrl |= set_mask;
    seg7_write(SEG7_CTRL, ctrl);
}

void seg7_init(void)
{
    /*
     * Default bring-up:
     * - enabled
     * - FULL6_HEX mode
     * - live source
     * - freeze off
     * - all decimal points off
     * - no blanking
     * - software value = 0
     */
    seg7_set_sw_value(0u);
    seg7_set_dp_n(0x3Fu);
    seg7_set_blank(0u);

    seg7_write(
        SEG7_CTRL,
        SEG7_EN_MASK |
        (SEG7_MODE_FULL6_HEX << SEG7_MODE_LSB)
    );
}

void seg7_enable(bool enable)
{
    seg7_update_ctrl(
        SEG7_EN_MASK,
        enable ? SEG7_EN_MASK : 0u
    );
}

void seg7_set_mode(uint32_t mode)
{
    mode &= 0x7u;

    seg7_update_ctrl(
        SEG7_MODE_MASK,
        (mode << SEG7_MODE_LSB)
    );
}

void seg7_select_live(void)
{
    seg7_update_ctrl(SEG7_SRC_SEL_MASK, 0u);
}

void seg7_select_software(void)
{
    seg7_update_ctrl(SEG7_SRC_SEL_MASK, SEG7_SRC_SEL_MASK);
}

void seg7_set_freeze(bool enable)
{
    seg7_update_ctrl(
        SEG7_FREEZE_MASK,
        enable ? SEG7_FREEZE_MASK : 0u
    );
}

void seg7_snapshot(void)
{
    /*
     * SNAPSHOT is W1P in hardware.
     * Write CTRL with the snapshot bit set to generate the pulse.
     */
    uint32_t ctrl = seg7_get_ctrl();
    ctrl |= SEG7_SNAPSHOT_MASK;
    seg7_write(SEG7_CTRL, ctrl);
}

void seg7_set_sw_value(uint32_t value24)
{
    seg7_write(SEG7_SW_VALUE, value24 & 0x00FFFFFFu);
}

void seg7_set_dp_n(uint32_t dp_n_6bit)
{
    seg7_write(SEG7_DP_N, dp_n_6bit & 0x3Fu);
}

void seg7_set_blank(uint32_t blank_6bit)
{
    seg7_write(SEG7_BLANK, blank_6bit & 0x3Fu);
}

uint32_t seg7_get_ctrl(void)
{
    return seg7_read(SEG7_CTRL);
}

uint32_t seg7_get_status(void)
{
    return seg7_read(SEG7_STATUS);
}

uint32_t seg7_get_live_value(void)
{
    return seg7_read(SEG7_LIVE_VALUE) & 0x00FFFFFFu;
}

uint32_t seg7_get_frozen_value(void)
{
    return seg7_read(SEG7_FROZEN_VALUE) & 0x00FFFFFFu;
}

uint32_t seg7_get_active_value(void)
{
    return seg7_read(SEG7_ACTIVE_VALUE) & 0x00FFFFFFu;
}

uint32_t seg7_pack_hex6(uint8_t dig5,
                        uint8_t dig4,
                        uint8_t dig3,
                        uint8_t dig2,
                        uint8_t dig1,
                        uint8_t dig0)
{
    return (((uint32_t)(dig5 & 0xFu)) << 20) |
           (((uint32_t)(dig4 & 0xFu)) << 16) |
           (((uint32_t)(dig3 & 0xFu)) << 12) |
           (((uint32_t)(dig2 & 0xFu)) <<  8) |
           (((uint32_t)(dig1 & 0xFu)) <<  4) |
           (((uint32_t)(dig0 & 0xFu)) <<  0);
}