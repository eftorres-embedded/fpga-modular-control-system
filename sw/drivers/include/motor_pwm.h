#ifndef MOTOR_PWM_H
#define MOTOR_PWM_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "pwm_regs.h"

/*----------------------------------------------------------------------------
 * Motor-PWM wrapper for the MOTOR_PWM_BASE instance only.
 *
 * This layer sits on top of pwm_regs.h/.c and provides motor-oriented shadow
 * state plus one-shot apply semantics.
 *
 * Convention used here:
 * - direction bit = 0 -> forward / normal polarity
 * - direction bit = 1 -> reverse polarity
 *
 * The final electrical effect still depends on your downstream H-bridge adapter
 * logic. This wrapper only manages the PWM/mask register model.
 *----------------------------------------------------------------------------*/

#define MOTOR_PWM_LEFT_CHANNEL    0u
#define MOTOR_PWM_RIGHT_CHANNEL   1u

typedef enum
{
    MOTOR_PWM_OK = 0,
    MOTOR_PWM_ERR_NOT_INITIALIZED = -1,
    MOTOR_PWM_ERR_BAD_CHANNEL = -2,
    MOTOR_PWM_ERR_BAD_CHANNEL_COUNT = -3,
    MOTOR_PWM_ERR_DUTY_GT_PERIOD = -4,
    MOTOR_PWM_ERR_BRAKE_AND_COAST = -5
} motor_pwm_status_t;

/* Core setup / apply */
motor_pwm_status_t motor_pwm_init(size_t channels, uint32_t period);
motor_pwm_status_t motor_pwm_set_period(uint32_t period);
uint32_t motor_pwm_get_period(void);
motor_pwm_status_t motor_pwm_apply(void);
motor_pwm_status_t motor_pwm_all_off(void);

/* Low-level per-channel control */
motor_pwm_status_t motor_pwm_set_raw(
    uint32_t channel,
    uint32_t duty,
    bool     reverse,
    bool     brake,
    bool     coast,
    bool     enable);

/* Signed command helper:
 *  positive = forward
 *  negative = reverse
 *  zero     = off
 */
motor_pwm_status_t motor_pwm_set_signed(uint32_t channel, int32_t command);

/* Convenience helpers */
motor_pwm_status_t motor_pwm_brake(uint32_t channel);
motor_pwm_status_t motor_pwm_coast(uint32_t channel);
motor_pwm_status_t motor_pwm_disable(uint32_t channel);
motor_pwm_status_t motor_pwm_brake_all(void);
motor_pwm_status_t motor_pwm_coast_all(void);

#endif /* MOTOR_PWM_H */
