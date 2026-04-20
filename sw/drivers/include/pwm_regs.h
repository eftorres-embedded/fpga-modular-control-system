#ifndef PWM_REGS_H
#define PWM_REGS_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/*----------------------------------------------------------------------------
 * PWM instance base addresses
 *
 * User-selected local addresses for the two PWM instances in this project.
 * - MOTOR_PWM_BASE : PWM subsystem with H-bridge extension window
 * - LED_PWM_BASE   : common PWM-only instance for LEDs / generic outputs
 *----------------------------------------------------------------------------*/
#ifndef MOTOR_PWM_BASE
#define MOTOR_PWM_BASE   0x00030000u
#endif

#ifndef LED_PWM_BASE
#define LED_PWM_BASE     0x00032000u
#endif

/*----------------------------------------------------------------------------
 * Register offsets - common PWM block
 *----------------------------------------------------------------------------*/
#define PWM_REG_CTRL_OFFSET          0x00u
#define PWM_REG_PERIOD_OFFSET        0x04u
#define PWM_REG_APPLY_OFFSET         0x08u
#define PWM_REG_CH_ENABLE_OFFSET     0x0Cu
#define PWM_REG_STATUS_OFFSET        0x10u
#define PWM_REG_CNT_OFFSET           0x14u
#define PWM_REG_DUTY_BASE_OFFSET     0x20u

/*----------------------------------------------------------------------------
 * Register offsets - H-bridge extension
 *
 * These are meaningful only for the motor-control PWM instance.
 *----------------------------------------------------------------------------*/
#define PWM_REG_DIR_MASK_OFFSET      0x40u
#define PWM_REG_BRAKE_MASK_OFFSET    0x44u
#define PWM_REG_COAST_MASK_OFFSET    0x48u

/*----------------------------------------------------------------------------
 * CTRL register bits
 *----------------------------------------------------------------------------*/
#define PWM_CTRL_ENABLE_BIT          0u
#define PWM_CTRL_ENABLE              (1u << PWM_CTRL_ENABLE_BIT)

/*----------------------------------------------------------------------------
 * STATUS register bits
 *----------------------------------------------------------------------------*/
#define PWM_STATUS_PERIOD_END_BIT      0u
#define PWM_STATUS_APPLY_PENDING_BIT   1u
#define PWM_STATUS_ACTIVE_ENABLE_BIT   2u

#define PWM_STATUS_PERIOD_END        (1u << PWM_STATUS_PERIOD_END_BIT)
#define PWM_STATUS_APPLY_PENDING     (1u << PWM_STATUS_APPLY_PENDING_BIT)
#define PWM_STATUS_ACTIVE_ENABLE     (1u << PWM_STATUS_ACTIVE_ENABLE_BIT)

/*----------------------------------------------------------------------------
 * Misc constants
 *----------------------------------------------------------------------------*/
#define PWM_MAX_CHANNELS             32u

/*----------------------------------------------------------------------------
 * Simple status / error codes for pwm_regs.c helper functions
 *----------------------------------------------------------------------------*/
typedef enum
{
    PWM_OK = 0,
    PWM_ERR_NULL_PTR = -1,
    PWM_ERR_BAD_CHANNEL_COUNT = -2
} pwm_status_t;

/*----------------------------------------------------------------------------
 * Generic MMIO access helpers
 *----------------------------------------------------------------------------*/
#define PWM_REG32(base, offset) \
    (*(volatile uint32_t *)((uintptr_t)(base) + (uintptr_t)(offset)))

#define PWM_REG_CTRL(base)           PWM_REG32((base), PWM_REG_CTRL_OFFSET)
#define PWM_REG_PERIOD(base)         PWM_REG32((base), PWM_REG_PERIOD_OFFSET)
#define PWM_REG_APPLY(base)          PWM_REG32((base), PWM_REG_APPLY_OFFSET)
#define PWM_REG_CH_ENABLE(base)      PWM_REG32((base), PWM_REG_CH_ENABLE_OFFSET)
#define PWM_REG_STATUS(base)         PWM_REG32((base), PWM_REG_STATUS_OFFSET)
#define PWM_REG_CNT(base)            PWM_REG32((base), PWM_REG_CNT_OFFSET)

#define PWM_REG_DIR_MASK(base)       PWM_REG32((base), PWM_REG_DIR_MASK_OFFSET)
#define PWM_REG_BRAKE_MASK(base)     PWM_REG32((base), PWM_REG_BRAKE_MASK_OFFSET)
#define PWM_REG_COAST_MASK(base)     PWM_REG32((base), PWM_REG_COAST_MASK_OFFSET)

#define PWM_REG_DUTY_OFFSET(ch)      (PWM_REG_DUTY_BASE_OFFSET + (4u * (uint32_t)(ch)))
#define PWM_REG_DUTY(base, ch)       PWM_REG32((base), PWM_REG_DUTY_OFFSET(ch))

/*----------------------------------------------------------------------------
 * Low-level MMIO helpers - common PWM block
 *----------------------------------------------------------------------------*/
static inline uint32_t pwm_ctrl_read(uint32_t base)          { return PWM_REG_CTRL(base); }
static inline uint32_t pwm_status_read(uint32_t base)        { return PWM_REG_STATUS(base); }
static inline uint32_t pwm_period_read(uint32_t base)        { return PWM_REG_PERIOD(base); }
static inline uint32_t pwm_counter_read(uint32_t base)       { return PWM_REG_CNT(base); }
static inline uint32_t pwm_ch_enable_read(uint32_t base)     { return PWM_REG_CH_ENABLE(base); }

static inline void pwm_ctrl_write(uint32_t base, uint32_t value)   { PWM_REG_CTRL(base) = value; }
static inline void pwm_write_period(uint32_t base, uint32_t value) { PWM_REG_PERIOD(base) = value; }
static inline void pwm_write_ch_enable(uint32_t base, uint32_t m)  { PWM_REG_CH_ENABLE(base) = m; }

/*
 * REG_APPLY is a write-one pulse action register.
 * Writing bit 0 = 1 requests shadow -> active commit.
 */
static inline void pwm_apply(uint32_t base)                  { PWM_REG_APPLY(base) = 1u; }

/*----------------------------------------------------------------------------
 * Duty-bank helpers
 *----------------------------------------------------------------------------*/
static inline void pwm_write_duty(uint32_t base, uint32_t ch, uint32_t value)
{
    PWM_REG_DUTY(base, ch) = value;
}

static inline uint32_t pwm_read_duty(uint32_t base, uint32_t ch)
{
    return PWM_REG_DUTY(base, ch);
}

/*----------------------------------------------------------------------------
 * Common status helpers
 *----------------------------------------------------------------------------*/
static inline bool pwm_period_end_seen(uint32_t base)
{
    return (PWM_REG_STATUS(base) & PWM_STATUS_PERIOD_END) != 0u;
}

static inline bool pwm_apply_pending(uint32_t base)
{
    return (PWM_REG_STATUS(base) & PWM_STATUS_APPLY_PENDING) != 0u;
}

static inline bool pwm_active_enabled(uint32_t base)
{
    return (PWM_REG_STATUS(base) & PWM_STATUS_ACTIVE_ENABLE) != 0u;
}

/*----------------------------------------------------------------------------
 * Common control helpers
 *----------------------------------------------------------------------------*/
static inline void pwm_enable_shadow(uint32_t base)
{
    PWM_REG_CTRL(base) = pwm_ctrl_read(base) | PWM_CTRL_ENABLE;
}

static inline void pwm_disable_shadow(uint32_t base)
{
    PWM_REG_CTRL(base) = pwm_ctrl_read(base) & ~PWM_CTRL_ENABLE;
}

/*----------------------------------------------------------------------------
 * H-bridge extension helpers
 *
 * Use these only with MOTOR_PWM_BASE.
 * They are shadow registers, so write them first and then call pwm_apply() so
 * they commit atomically with period/duty/channel-enable updates.
 *----------------------------------------------------------------------------*/
static inline uint32_t pwm_dir_mask_read(uint32_t base)      { return PWM_REG_DIR_MASK(base); }
static inline uint32_t pwm_brake_mask_read(uint32_t base)    { return PWM_REG_BRAKE_MASK(base); }
static inline uint32_t pwm_coast_mask_read(uint32_t base)    { return PWM_REG_COAST_MASK(base); }

static inline void pwm_write_dir_mask(uint32_t base, uint32_t m)   { PWM_REG_DIR_MASK(base) = m; }
static inline void pwm_write_brake_mask(uint32_t base, uint32_t m) { PWM_REG_BRAKE_MASK(base) = m; }
static inline void pwm_write_coast_mask(uint32_t base, uint32_t m) { PWM_REG_COAST_MASK(base) = m; }

/*----------------------------------------------------------------------------
 * pwm_regs.c API
 *
 * These helper functions implement the COMMON PWM programming flow that is
 * shared by both LED and motor-control instances.
 *
 * - Use pwm_common_prepare_frame() when you want to stage common PWM shadow
 *   state first, then optionally write motor dir/brake/coast masks, then call
 *   pwm_apply(base) yourself for one atomic commit.
 *
 * - Use pwm_common_apply_frame() when you only need the common PWM registers
 *   and want the helper to commit immediately.
 *
 * - Use pwm_common_all_off() for a safe fully-disabled state.
 *----------------------------------------------------------------------------*/
pwm_status_t pwm_common_prepare_frame(
    uint32_t        base,
    uint32_t        period,
    const uint32_t *duty_values,
    size_t          channels,
    uint32_t        ch_enable_mask,
    bool            enable_core);

pwm_status_t pwm_common_apply_frame(
    uint32_t        base,
    uint32_t        period,
    const uint32_t *duty_values,
    size_t          channels,
    uint32_t        ch_enable_mask,
    bool            enable_core);

pwm_status_t pwm_common_all_off(
    uint32_t        base,
    size_t          channels);

#endif /* PWM_REGS_H */
