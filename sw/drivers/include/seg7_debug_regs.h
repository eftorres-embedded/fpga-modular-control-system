#ifndef SEG7_DEBUG_REGS_H
#define SEG7_DEBUG_REGS_H

#include <stdint.h>
#include <stdbool.h>

#include "system.h"

#ifndef SEG7_DEBUG_BASE
    #if defined(SEG7_DEBUG_0_BASE)
        #define SEG7_DEBUG_BASE  SEG7_DEBUG_0_BASE
    #else
        #define SEG7_DEBUG_BASE  0x00035000u
    #endif
#endif

/* --------------------------------------------------------------------------
 * Register offsets
 * -------------------------------------------------------------------------- */
#define SEG7_CTRL           0x00u
#define SEG7_SW_VALUE       0x04u
#define SEG7_DP_N           0x08u
#define SEG7_BLANK          0x0Cu
#define SEG7_LIVE_VALUE     0x10u
#define SEG7_FROZEN_VALUE   0x14u
#define SEG7_ACTIVE_VALUE   0x18u
#define SEG7_STATUS         0x1Cu

/* --------------------------------------------------------------------------
 * CTRL / STATUS bit fields
 * -------------------------------------------------------------------------- */
#define SEG7_EN_BIT         0u
#define SEG7_MODE_LSB       1u
#define SEG7_SRC_SEL_BIT    4u
#define SEG7_FREEZE_BIT     5u
#define SEG7_SNAPSHOT_BIT   6u

#define SEG7_EN_MASK        (1u << SEG7_EN_BIT)
#define SEG7_MODE_MASK      (0x7u << SEG7_MODE_LSB)
#define SEG7_SRC_SEL_MASK   (1u << SEG7_SRC_SEL_BIT)
#define SEG7_FREEZE_MASK    (1u << SEG7_FREEZE_BIT)
#define SEG7_SNAPSHOT_MASK  (1u << SEG7_SNAPSHOT_BIT)

/* --------------------------------------------------------------------------
 * Mode encodings
 * -------------------------------------------------------------------------- */
#define SEG7_MODE_FULL6_HEX     0u
#define SEG7_MODE_SPLIT2X12     1u
#define SEG7_MODE_SPLIT3X8      2u
#define SEG7_MODE_DIGIT_RAW     3u

/* --------------------------------------------------------------------------
 * Source select
 * -------------------------------------------------------------------------- */
#define SEG7_SRC_LIVE           0u
#define SEG7_SRC_SOFTWARE       1u

/* --------------------------------------------------------------------------
 * API
 * -------------------------------------------------------------------------- */
void     seg7_init(void);
void     seg7_enable(bool enable);
void     seg7_set_mode(uint32_t mode);

void     seg7_select_live(void);
void     seg7_select_software(void);

void     seg7_set_freeze(bool enable);
void     seg7_snapshot(void);

void     seg7_set_sw_value(uint32_t value24);
void     seg7_set_dp_n(uint32_t dp_n_6bit);
void     seg7_set_blank(uint32_t blank_6bit);

uint32_t seg7_get_ctrl(void);
uint32_t seg7_get_status(void);
uint32_t seg7_get_live_value(void);
uint32_t seg7_get_frozen_value(void);
uint32_t seg7_get_active_value(void);

uint32_t seg7_pack_hex6(uint8_t dig5,
                        uint8_t dig4,
                        uint8_t dig3,
                        uint8_t dig2,
                        uint8_t dig1,
                        uint8_t dig0);

#endif /* SEG7_DEBUG_REGS_H */