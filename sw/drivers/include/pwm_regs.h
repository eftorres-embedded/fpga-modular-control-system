#ifndef PWM_REGS_H
#define PWM_REGS_H

#include <stdint.h>
#include "user_define_system.h"

/*----------------------------------------------------------------------------
 * Register offsets
 *----------------------------------------------------------------------------*/
#define PWM_REG_CTRL_OFFSET        0x00u
#define PWM_REG_PERIOD_OFFSET      0x04u
#define PWM_REG_APPLY_OFFSET       0x08u
#define PWM_REG_CH_ENABLE_OFFSET   0x0Cu
#define PWM_REG_STATUS_OFFSET      0x10u
#define PWM_REG_CNT_OFFSET         0x14u
#define PWM_REG_DUTY_BASE_OFFSET   0x20u

#define PWM_REG_DUTY_OFFSET(ch) \
    (PWM_REG_DUTY_BASE_OFFSET + (4u * (uint32_t)(ch)))

/*----------------------------------------------------------------------------
 * Simple MMIO helper
 *----------------------------------------------------------------------------*/
#define PWM_REG32(base, offset) \
    (*(volatile uint32_t *)((uintptr_t)(base) + (uintptr_t)(offset)))

/*----------------------------------------------------------------------------
 * Basic API
 *----------------------------------------------------------------------------*/
static inline void pwm_set_period(uint32_t base, uint32_t period)
{
    PWM_REG32(base, PWM_REG_PERIOD_OFFSET) = period;
}

static inline void pwm_set_ctrl(uint32_t base, uint32_t ctrl)
{
    PWM_REG32(base, PWM_REG_CTRL_OFFSET) = ctrl;
}

static inline void pwm_set_ch_enable(uint32_t base, uint32_t channels)
{
    PWM_REG32(base, PWM_REG_CH_ENABLE_OFFSET) = channels;
}

static inline uint32_t pwm_read_cnt(uint32_t base)
{
    return PWM_REG32(base, PWM_REG_CNT_OFFSET);
}

/* Small extra helper for multi-channel PWM instances */
static inline void pwm_set_duty_ch(uint32_t base, uint32_t channel, uint32_t duty)
{
    PWM_REG32(base, PWM_REG_DUTY_OFFSET(channel)) = duty;
}

static inline uint32_t pwm_read_max_duty(uint32_t base)
{
    return PWM_REG32(base, PWM_REG_PERIOD_OFFSET);
}

static inline void pwm_apply(uint32_t base)
{
    PWM_REG32(base, PWM_REG_APPLY_OFFSET) = 1u;
}

#endif /* PWM_REGS_H */