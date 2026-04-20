#include "motor_pwm.h"

/*----------------------------------------------------------------------------
 * Internal shadow state for the MOTOR_PWM_BASE instance.
 *----------------------------------------------------------------------------*/
static bool     g_motor_pwm_initialized = false;
static size_t   g_motor_pwm_channels    = 0u;
static uint32_t g_motor_pwm_period      = 0u;
static uint32_t g_motor_pwm_duty[PWM_MAX_CHANNELS];
static uint32_t g_motor_pwm_enable_mask = 0u;
static uint32_t g_motor_pwm_dir_mask    = 0u;
static uint32_t g_motor_pwm_brake_mask  = 0u;
static uint32_t g_motor_pwm_coast_mask  = 0u;

/*----------------------------------------------------------------------------
 * Internal helpers
 *----------------------------------------------------------------------------*/
static motor_pwm_status_t motor_pwm_validate_channel(uint32_t channel)
{
    if (!g_motor_pwm_initialized) {
        return MOTOR_PWM_ERR_NOT_INITIALIZED;
    }

    if (channel >= g_motor_pwm_channels) {
        return MOTOR_PWM_ERR_BAD_CHANNEL;
    }

    return MOTOR_PWM_OK;
}

static inline uint32_t motor_pwm_bit(uint32_t channel)
{
    return (1u << channel);
}

/*----------------------------------------------------------------------------
 * Public API
 *----------------------------------------------------------------------------*/
motor_pwm_status_t motor_pwm_init(size_t channels, uint32_t period)
{
    size_t i;

    if ((channels == 0u) || (channels > PWM_MAX_CHANNELS)) {
        return MOTOR_PWM_ERR_BAD_CHANNEL_COUNT;
    }

    g_motor_pwm_initialized = true;
    g_motor_pwm_channels    = channels;
    g_motor_pwm_period      = period;
    g_motor_pwm_enable_mask = 0u;
    g_motor_pwm_dir_mask    = 0u;
    g_motor_pwm_brake_mask  = 0u;
    g_motor_pwm_coast_mask  = 0u;

    for (i = 0u; i < PWM_MAX_CHANNELS; ++i) {
        g_motor_pwm_duty[i] = 0u;
    }

    return motor_pwm_all_off();
}

motor_pwm_status_t motor_pwm_set_period(uint32_t period)
{
    if (!g_motor_pwm_initialized) {
        return MOTOR_PWM_ERR_NOT_INITIALIZED;
    }

    g_motor_pwm_period = period;
    return MOTOR_PWM_OK;
}

uint32_t motor_pwm_get_period(void)
{
    return g_motor_pwm_period;
}

motor_pwm_status_t motor_pwm_set_raw(
    uint32_t channel,
    uint32_t duty,
    bool     reverse,
    bool     brake,
    bool     coast,
    bool     enable)
{
    uint32_t bit;
    motor_pwm_status_t st;

    st = motor_pwm_validate_channel(channel);
    if (st != MOTOR_PWM_OK) {
        return st;
    }

    if (brake && coast) {
        return MOTOR_PWM_ERR_BRAKE_AND_COAST;
    }

    if (duty > g_motor_pwm_period) {
        return MOTOR_PWM_ERR_DUTY_GT_PERIOD;
    }

    bit = motor_pwm_bit(channel);

    g_motor_pwm_duty[channel] = duty;

    if (enable) {
        g_motor_pwm_enable_mask |= bit;
    } else {
        g_motor_pwm_enable_mask &= ~bit;
    }

    if (reverse) {
        g_motor_pwm_dir_mask |= bit;
    } else {
        g_motor_pwm_dir_mask &= ~bit;
    }

    if (brake) {
        g_motor_pwm_brake_mask |= bit;
    } else {
        g_motor_pwm_brake_mask &= ~bit;
    }

    if (coast) {
        g_motor_pwm_coast_mask |= bit;
    } else {
        g_motor_pwm_coast_mask &= ~bit;
    }

    return MOTOR_PWM_OK;
}

motor_pwm_status_t motor_pwm_set_signed(uint32_t channel, int32_t command)
{
    uint32_t duty;
    bool reverse;

    if (!g_motor_pwm_initialized) {
        return MOTOR_PWM_ERR_NOT_INITIALIZED;
    }

    if ((command > (int32_t)g_motor_pwm_period) ||
        (command < -(int32_t)g_motor_pwm_period)) {
        return MOTOR_PWM_ERR_DUTY_GT_PERIOD;
    }

    if (command == 0) {
        return motor_pwm_set_raw(channel, 0u, false, false, false, false);
    }

    reverse = (command < 0);
    duty    = (uint32_t)(reverse ? -command : command);

    return motor_pwm_set_raw(channel, duty, reverse, false, false, true);
}

motor_pwm_status_t motor_pwm_apply(void)
{
    pwm_status_t st;

    if (!g_motor_pwm_initialized) {
        return MOTOR_PWM_ERR_NOT_INITIALIZED;
    }

    st = pwm_common_prepare_frame(MOTOR_PWM_BASE,
                                  g_motor_pwm_period,
                                  g_motor_pwm_duty,
                                  g_motor_pwm_channels,
                                  g_motor_pwm_enable_mask,
                                  true);
    if (st != PWM_OK) {
        return MOTOR_PWM_ERR_BAD_CHANNEL_COUNT;
    }

    pwm_write_dir_mask(MOTOR_PWM_BASE,   g_motor_pwm_dir_mask);
    pwm_write_brake_mask(MOTOR_PWM_BASE, g_motor_pwm_brake_mask);
    pwm_write_coast_mask(MOTOR_PWM_BASE, g_motor_pwm_coast_mask);

    pwm_apply(MOTOR_PWM_BASE);

    return MOTOR_PWM_OK;
}

motor_pwm_status_t motor_pwm_all_off(void)
{
    size_t i;

    if (!g_motor_pwm_initialized) {
        return MOTOR_PWM_ERR_NOT_INITIALIZED;
    }

    for (i = 0u; i < g_motor_pwm_channels; ++i) {
        g_motor_pwm_duty[i] = 0u;
    }

    g_motor_pwm_enable_mask = 0u;
    g_motor_pwm_dir_mask    = 0u;
    g_motor_pwm_brake_mask  = 0u;
    g_motor_pwm_coast_mask  = 0u;

    return motor_pwm_apply();
}

motor_pwm_status_t motor_pwm_brake(uint32_t channel)
{
    return motor_pwm_set_raw(channel, 0u, false, true, false, true);
}

motor_pwm_status_t motor_pwm_coast(uint32_t channel)
{
    return motor_pwm_set_raw(channel, 0u, false, false, true, false);
}

motor_pwm_status_t motor_pwm_disable(uint32_t channel)
{
    return motor_pwm_set_raw(channel, 0u, false, false, false, false);
}

motor_pwm_status_t motor_pwm_brake_all(void)
{
    motor_pwm_status_t st;

    st = motor_pwm_brake(MOTOR_PWM_LEFT_CHANNEL);
    if (st != MOTOR_PWM_OK) {
        return st;
    }

    st = motor_pwm_brake(MOTOR_PWM_RIGHT_CHANNEL);
    if (st != MOTOR_PWM_OK) {
        return st;
    }

    return motor_pwm_apply();
}

motor_pwm_status_t motor_pwm_coast_all(void)
{
    motor_pwm_status_t st;

    st = motor_pwm_coast(MOTOR_PWM_LEFT_CHANNEL);
    if (st != MOTOR_PWM_OK) {
        return st;
    }

    st = motor_pwm_coast(MOTOR_PWM_RIGHT_CHANNEL);
    if (st != MOTOR_PWM_OK) {
        return st;
    }

    return motor_pwm_apply();
}
