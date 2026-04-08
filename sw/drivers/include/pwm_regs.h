#ifndef PWM_REGS_H
#define PWM_REGS_H

#include <stdint.h>
#include <stdbool.h>

/* -------------------------------------------------------------------------
 * PWM base address
 * Update this if the Platform Designer base address changes.
 * ------------------------------------------------------------------------- */
#define PWM_BASE_ADDR               0x00030000u

/* -------------------------------------------------------------------------
 * Register offsets
 * ------------------------------------------------------------------------- */
#define PWM_REG_CTRL_OFFSET         0x00u
#define PWM_REG_PERIOD_OFFSET       0x04u
#define PWM_REG_DUTY_OFFSET         0x08u
#define PWM_REG_APPLY_OFFSET        0x0Cu
#define PWM_REG_STATUS_OFFSET       0x10u
#define PWM_REG_CNT_OFFSET          0x14u

/* -------------------------------------------------------------------------
 * Absolute register addresses
 * ------------------------------------------------------------------------- */
#define PWM_REG_CTRL_ADDR           (PWM_BASE_ADDR + PWM_REG_CTRL_OFFSET)
#define PWM_REG_PERIOD_ADDR         (PWM_BASE_ADDR + PWM_REG_PERIOD_OFFSET)
#define PWM_REG_DUTY_ADDR           (PWM_BASE_ADDR + PWM_REG_DUTY_OFFSET)
#define PWM_REG_APPLY_ADDR          (PWM_BASE_ADDR + PWM_REG_APPLY_OFFSET)
#define PWM_REG_STATUS_ADDR         (PWM_BASE_ADDR + PWM_REG_STATUS_OFFSET)
#define PWM_REG_CNT_ADDR            (PWM_BASE_ADDR + PWM_REG_CNT_OFFSET)

/* -------------------------------------------------------------------------
 * Register access macros
 * ------------------------------------------------------------------------- */
#define PWM_REG_CTRL                (*(volatile uint32_t *)(PWM_REG_CTRL_ADDR))
#define PWM_REG_PERIOD              (*(volatile uint32_t *)(PWM_REG_PERIOD_ADDR))
#define PWM_REG_DUTY                (*(volatile uint32_t *)(PWM_REG_DUTY_ADDR))
#define PWM_REG_APPLY               (*(volatile uint32_t *)(PWM_REG_APPLY_ADDR))
#define PWM_REG_STATUS              (*(volatile uint32_t *)(PWM_REG_STATUS_ADDR))
#define PWM_REG_CNT                 (*(volatile uint32_t *)(PWM_REG_CNT_ADDR))

/* -------------------------------------------------------------------------
 * CTRL register bits
 *
 * These are SHADOW control bits from software's point of view.
 * They do not affect the live PWM output until APPLY is written.
 * ------------------------------------------------------------------------- */
#define PWM_CTRL_ENABLE_BIT                 0u
#define PWM_CTRL_USE_DEFAULT_DUTY_BIT       1u

#define PWM_CTRL_ENABLE                     (1u << PWM_CTRL_ENABLE_BIT)
#define PWM_CTRL_USE_DEFAULT_DUTY           (1u << PWM_CTRL_USE_DEFAULT_DUTY_BIT)

/* -------------------------------------------------------------------------
 * APPLY register bits
 * ------------------------------------------------------------------------- */
#define PWM_APPLY_COMMIT_BIT                0u
#define PWM_APPLY_COMMIT                    (1u << PWM_APPLY_COMMIT_BIT)

/* -------------------------------------------------------------------------
 * STATUS register bits
 *
 * Based on pwm_regs.sv:
 *   bit 0 = period_end_i
 *   bit 1 = apply_pending
 *   bit 2 = active enable
 *   bit 3 = active use_default_duty
 * ------------------------------------------------------------------------- */
#define PWM_STATUS_PERIOD_END_BIT           0u
#define PWM_STATUS_APPLY_PENDING_BIT        1u
#define PWM_STATUS_ACTIVE_ENABLE_BIT        2u
#define PWM_STATUS_ACTIVE_USE_DEFAULT_BIT   3u

#define PWM_STATUS_PERIOD_END               (1u << PWM_STATUS_PERIOD_END_BIT)
#define PWM_STATUS_APPLY_PENDING            (1u << PWM_STATUS_APPLY_PENDING_BIT)
#define PWM_STATUS_ACTIVE_ENABLE            (1u << PWM_STATUS_ACTIVE_ENABLE_BIT)
#define PWM_STATUS_ACTIVE_USE_DEFAULT       (1u << PWM_STATUS_ACTIVE_USE_DEFAULT_BIT)

/* -------------------------------------------------------------------------
 * Low-level MMIO helpers
 * ------------------------------------------------------------------------- */
static inline void pwm_write_ctrl(uint32_t value)
{
    PWM_REG_CTRL = value;
}

static inline uint32_t pwm_read_ctrl(void)
{
    return PWM_REG_CTRL;
}

static inline void pwm_write_period(uint32_t value)
{
    PWM_REG_PERIOD = value;
}

static inline uint32_t pwm_read_period(void)
{
    return PWM_REG_PERIOD;
}

static inline void pwm_write_duty(uint32_t value)
{
    PWM_REG_DUTY = value;
}

static inline uint32_t pwm_read_duty(void)
{
    return PWM_REG_DUTY;
}

static inline void pwm_apply(void)
{
    PWM_REG_APPLY = PWM_APPLY_COMMIT;
}

static inline uint32_t pwm_read_status(void)
{
    return PWM_REG_STATUS;
}

static inline uint32_t pwm_read_counter(void)
{
    return PWM_REG_CNT;
}

static inline bool pwm_apply_pending(void)
{
    return (PWM_REG_STATUS & PWM_STATUS_APPLY_PENDING) != 0u;
}

static inline bool pwm_active_enabled(void)
{
    return (PWM_REG_STATUS & PWM_STATUS_ACTIVE_ENABLE) != 0u;
}

static inline bool pwm_active_use_default_duty(void)
{
    return (PWM_REG_STATUS & PWM_STATUS_ACTIVE_USE_DEFAULT) != 0u;
}

/* -------------------------------------------------------------------------
 * Driver API declarations
 * ------------------------------------------------------------------------- */
void pwm_init(void);
void pwm_set_shadow(uint32_t ctrl, uint32_t period, uint32_t duty);
void pwm_set_period_duty(uint32_t period, uint32_t duty);
void pwm_enable(uint32_t period, uint32_t duty);
void pwm_disable(void);
void pwm_enable_default_duty(uint32_t period);
void pwm_apply_blocking(void);

#endif /* PWM_REGS_H */