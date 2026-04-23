#ifndef MOTOR_PWM_H
#define MOTOR_PWM_H

#include <stdint.h>
#include "pwm_regs.h"

/*
 * Channel mask helper.
 *
 * Example:
 *   MOTOR_PWM_CH(0)
 *   MOTOR_PWM_CH(0) | MOTOR_PWM_CH(1)
 */
#define MOTOR_PWM_CH(ch)   (1u << (uint32_t)(ch))

static inline void motor_pwm_set_period(uint32_t period)
{
    pwm_set_period(MOTOR_PWM_BASE, period);
}

static inline void motor_pwm_set_ctrl(uint32_t ctrl)
{
    pwm_set_ctrl(MOTOR_PWM_BASE, ctrl);
}

/*
 * Full enable-mask write.
 * bit 0 -> channel 0
 * bit 1 -> channel 1
 * ...
 */
static inline void motor_pwm_enable_ch(uint32_t channels)
{
    pwm_set_ch_enable(MOTOR_PWM_BASE, channels);
}

static inline uint32_t motor_pwm_read_cnt(void)
{
    return pwm_read_cnt(MOTOR_PWM_BASE);
}

static inline uint32_t motor_pwm_read_max_duty(void)
{
    return pwm_read_max_duty(MOTOR_PWM_BASE);
}

static inline void motor_pwm_set_ch_duty(uint32_t channel, uint32_t duty)
{
    pwm_set_duty_ch(MOTOR_PWM_BASE, channel, duty);
}

/*
 * Full brake-mask write.
 * 1 = brake requested for that channel
 * 0 = brake not requested
 */
static inline void motor_pwm_brake_channels(uint32_t channels)
{
    pwm_write_brake_mask(MOTOR_PWM_BASE, channels);
}

/*
 * Full coast-mask write.
 * 1 = coast requested for that channel
 * 0 = coast not requested
 */
static inline void motor_pwm_coast_channels(uint32_t channels)
{
    pwm_write_coast_mask(MOTOR_PWM_BASE, channels);
}

/*
 * Full direction-mask write.
 * Bit meaning depends on your downstream H-bridge convention.
 */
static inline void motor_pwm_dir_channels(uint32_t channels)
{
    pwm_write_dir_mask(MOTOR_PWM_BASE, channels);
}

static inline void motor_pwm_apply(void)
{
    pwm_apply(MOTOR_PWM_BASE);
}

#endif /* MOTOR_PWM_H */