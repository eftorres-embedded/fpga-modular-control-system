#include "pwm_regs.h"

/* -------------------------------------------------------------------------
 * Initialize PWM shadow registers to a safe default state and commit them.
 * ------------------------------------------------------------------------- */
void pwm_init(void)
{
    PWM_REG_CTRL   = 0u;
    PWM_REG_PERIOD = 0u;
    PWM_REG_DUTY   = 0u;
    PWM_REG_APPLY  = PWM_APPLY_COMMIT;
}

/* -------------------------------------------------------------------------
 * Write all shadow registers, then let software decide when to apply.
 * ------------------------------------------------------------------------- */
void pwm_set_shadow(uint32_t ctrl, uint32_t period, uint32_t duty)
{
    PWM_REG_CTRL   = ctrl;
    PWM_REG_PERIOD = period;
    PWM_REG_DUTY   = duty;
}

/* -------------------------------------------------------------------------
 * Convenience helper:
 * Update period and duty shadow registers only.
 * ------------------------------------------------------------------------- */
void pwm_set_period_duty(uint32_t period, uint32_t duty)
{
    PWM_REG_PERIOD = period;
    PWM_REG_DUTY   = duty;
}

/* -------------------------------------------------------------------------
 * Enable PWM with an explicit period and duty, then commit immediately.
 * ------------------------------------------------------------------------- */
void pwm_enable(uint32_t period, uint32_t duty)
{
    PWM_REG_CTRL   = PWM_CTRL_ENABLE;
    PWM_REG_PERIOD = period;
    PWM_REG_DUTY   = duty;
    PWM_REG_APPLY  = PWM_APPLY_COMMIT;
}

/* -------------------------------------------------------------------------
 * Disable PWM and commit that state.
 * ------------------------------------------------------------------------- */
void pwm_disable(void)
{
    PWM_REG_CTRL  = 0u;
    PWM_REG_APPLY = PWM_APPLY_COMMIT;
}

/* -------------------------------------------------------------------------
 * Enable PWM while requesting the core to use its default duty behavior.
 * Period is still provided by software.
 * ------------------------------------------------------------------------- */
void pwm_enable_default_duty(uint32_t period)
{
    PWM_REG_CTRL   = PWM_CTRL_ENABLE | PWM_CTRL_USE_DEFAULT_DUTY;
    PWM_REG_PERIOD = period;
    PWM_REG_APPLY  = PWM_APPLY_COMMIT;
}

/* -------------------------------------------------------------------------
 * Write APPLY and wait until the register block reports that no deferred
 * apply is pending anymore.
 *
 * Note:
 * - If APPLY_ON_PERIOD_END = 0 in RTL, this usually returns quickly.
 * - If APPLY_ON_PERIOD_END = 1, this waits until the synchronized commit
 *   has completed.
 * ------------------------------------------------------------------------- */
void pwm_apply_blocking(void)
{
    PWM_REG_APPLY = PWM_APPLY_COMMIT;

    while ((PWM_REG_STATUS & PWM_STATUS_APPLY_PENDING) != 0u) {
        /* wait */
    }
}