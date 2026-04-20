#include "pwm_regs.h"

/*----------------------------------------------------------------------------
 * Validate the channel count used by the helper functions.
 *----------------------------------------------------------------------------*/
static pwm_status_t pwm_validate_channel_count(size_t channels)
{
    if (channels > PWM_MAX_CHANNELS) {
        return PWM_ERR_BAD_CHANNEL_COUNT;
    }

    return PWM_OK;
}

/*----------------------------------------------------------------------------
 * Stage the COMMON PWM shadow register set only.
 *
 * This function does NOT call REG_APPLY.
 *
 * Why this is useful:
 * - LED/common instance: you may choose to call pwm_apply() immediately after.
 * - Motor/H-bridge instance: you can stage PERIOD/DUTY/CH_ENABLE/CTRL first,
 *   then also stage DIR/BRAKE/COAST masks, then call pwm_apply(base) ONCE so
 *   everything commits atomically together.
 *----------------------------------------------------------------------------*/
pwm_status_t pwm_common_prepare_frame(
    uint32_t        base,
    uint32_t        period,
    const uint32_t *duty_values,
    size_t          channels,
    uint32_t        ch_enable_mask,
    bool            enable_core)
{
    size_t i;
    pwm_status_t st;

    if ((duty_values == NULL) && (channels != 0u)) {
        return PWM_ERR_NULL_PTR;
    }

    st = pwm_validate_channel_count(channels);
    if (st != PWM_OK) {
        return st;
    }

    /* Shadow period register. */
    pwm_write_period(base, period);

    /* Shadow duty bank. */
    for (i = 0u; i < channels; ++i) {
        pwm_write_duty(base, (uint32_t)i, duty_values[i]);
    }

    /* Shadow channel-enable mask. */
    pwm_write_ch_enable(base, ch_enable_mask);

    /* Shadow global enable bit. */
    if (enable_core) {
        pwm_enable_shadow(base);
    } else {
        pwm_disable_shadow(base);
    }

    return PWM_OK;
}

/*----------------------------------------------------------------------------
 * Stage the COMMON PWM shadow register set and commit immediately.
 *
 * This helper is ideal for the LED/common instance.
 * For the motor instance, use pwm_common_prepare_frame() instead if you also
 * need to stage dir/brake/coast masks before the same commit point.
 *----------------------------------------------------------------------------*/
pwm_status_t pwm_common_apply_frame(
    uint32_t        base,
    uint32_t        period,
    const uint32_t *duty_values,
    size_t          channels,
    uint32_t        ch_enable_mask,
    bool            enable_core)
{
    pwm_status_t st;

    st = pwm_common_prepare_frame(base,
                                  period,
                                  duty_values,
                                  channels,
                                  ch_enable_mask,
                                  enable_core);
    if (st != PWM_OK) {
        return st;
    }

    pwm_apply(base);
    return PWM_OK;
}

/*----------------------------------------------------------------------------
 * Drive the PWM instance to a safe fully-off state and commit immediately.
 *
 * This helper is common to both LED and motor-control instances.
 * It only touches the COMMON PWM registers:
 *   - period = 0
 *   - all duty values = 0
 *   - ch_enable mask = 0
 *   - CTRL.ENABLE = 0
 *   - APPLY pulse issued
 *
 * For the motor-control instance, if you also want to shadow a particular
 * dir/brake/coast state, write those masks separately before calling pwm_apply().
 *----------------------------------------------------------------------------*/
pwm_status_t pwm_common_all_off(
    uint32_t        base,
    size_t          channels)
{
    size_t i;
    pwm_status_t st;

    st = pwm_validate_channel_count(channels);
    if (st != PWM_OK) {
        return st;
    }

    pwm_write_period(base, 0u);

    for (i = 0u; i < channels; ++i) {
        pwm_write_duty(base, (uint32_t)i, 0u);
    }

    pwm_write_ch_enable(base, 0u);
    pwm_disable_shadow(base);
    pwm_apply(base);

    return PWM_OK;
}
