#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

#include "system.h"
#include "io.h"
#include "motor_pwm.h"

/*----------------------------------------------------------------------------
 * Simple motor polarity test
 *
 * Goal:
 *   1) Apply a small positive command to both motors
 *   2) Stop
 *   3) Apply a small negative command to both motors
 *   4) Stop
 *   5) Print the key motor PWM registers after each change
 *
 * Run this with the robot on the stand so the wheels are free.
 *----------------------------------------------------------------------------*/

/* Common motor PWM register map */
#define REG_CTRL            0x00u
#define REG_PERIOD          0x04u
#define REG_APPLY           0x08u
#define REG_CH_ENABLE       0x0Cu
#define REG_STATUS          0x10u
#define REG_CNT             0x14u
#define REG_DUTY0           0x20u
#define REG_DUTY1           0x24u

/* H-bridge extension registers */
#define REG_DIR_MASK        0x40u
#define REG_BRAKE_MASK      0x44u
#define REG_COAST_MASK      0x48u

#define MOTOR_CHANNELS      2u
#define MOTOR_TEST_PERIOD   25000u
#define MOTOR_TEST_DUTY     5000
#define RUN_TIME_US         5000000u
#define STOP_TIME_US        1500000u

static uint32_t reg_read(uint32_t base, uint32_t offset)
{
    return IORD_32DIRECT(base, offset);
}

static void dump_motor_regs(const char *tag)
{
    uint32_t ctrl      = reg_read(MOTOR_PWM_BASE, REG_CTRL);
    uint32_t period    = reg_read(MOTOR_PWM_BASE, REG_PERIOD);
    uint32_t ch_en     = reg_read(MOTOR_PWM_BASE, REG_CH_ENABLE);
    uint32_t status    = reg_read(MOTOR_PWM_BASE, REG_STATUS);
    uint32_t cnt       = reg_read(MOTOR_PWM_BASE, REG_CNT);
    uint32_t duty0     = reg_read(MOTOR_PWM_BASE, REG_DUTY0);
    uint32_t duty1     = reg_read(MOTOR_PWM_BASE, REG_DUTY1);
    uint32_t dir_mask  = reg_read(MOTOR_PWM_BASE, REG_DIR_MASK);
    uint32_t brake     = reg_read(MOTOR_PWM_BASE, REG_BRAKE_MASK);
    uint32_t coast     = reg_read(MOTOR_PWM_BASE, REG_COAST_MASK);

    printf("\n[%s]\n", tag);
    printf("  MOTOR_PWM_BASE = 0x%08X\n", (unsigned)MOTOR_PWM_BASE);
    printf("  CTRL      = 0x%08lX\n", (unsigned long)ctrl);
    printf("  PERIOD    = %lu\n",     (unsigned long)period);
    printf("  CH_ENABLE = 0x%08lX\n", (unsigned long)ch_en);
    printf("  STATUS    = 0x%08lX\n", (unsigned long)status);
    printf("  CNT       = %lu\n",     (unsigned long)cnt);
    printf("  DUTY0     = %lu\n",     (unsigned long)duty0);
    printf("  DUTY1     = %lu\n",     (unsigned long)duty1);
    printf("  DIR_MASK  = 0x%08lX\n", (unsigned long)dir_mask);
    printf("  BRAKE     = 0x%08lX\n", (unsigned long)brake);
    printf("  COAST     = 0x%08lX\n", (unsigned long)coast);
}

static bool motor_apply_pair(int32_t left_cmd, int32_t right_cmd, const char *tag)
{
    motor_pwm_status_t st;

    st = motor_pwm_set_signed(MOTOR_PWM_LEFT_CHANNEL, left_cmd);
    if (st != MOTOR_PWM_OK) {
        printf("motor_pwm_set_signed(left=%ld) failed, status=%d\n",
               (long)left_cmd, (int)st);
        return false;
    }

    st = motor_pwm_set_signed(MOTOR_PWM_RIGHT_CHANNEL, right_cmd);
    if (st != MOTOR_PWM_OK) {
        printf("motor_pwm_set_signed(right=%ld) failed, status=%d\n",
               (long)right_cmd, (int)st);
        return false;
    }

    st = motor_pwm_apply();
    if (st != MOTOR_PWM_OK) {
        printf("motor_pwm_apply failed, status=%d\n", (int)st);
        return false;
    }

    printf("\nApplied command: left=%ld, right=%ld\n",
           (long)left_cmd, (long)right_cmd);

    dump_motor_regs(tag);
    return true;
}

int main(void)
{
    motor_pwm_status_t st;

    printf("\n=== SIMPLE MOTOR POLARITY TEST ===\n");
    printf("Robot should be on stand with wheels free.\n");
    printf("Positive test duty  = %d\n", MOTOR_TEST_DUTY);
    printf("Negative test duty  = %d\n", -MOTOR_TEST_DUTY);
    printf("PWM period          = %lu\n", (unsigned long)MOTOR_TEST_PERIOD);
    printf("Motor PWM base      = 0x%08X\n", (unsigned)MOTOR_PWM_BASE);

    st = motor_pwm_init(MOTOR_CHANNELS, MOTOR_TEST_PERIOD);
    if (st != MOTOR_PWM_OK) {
        printf("motor_pwm_init failed, status=%d\n", (int)st);
        while (1) {
            usleep(250000);
        }
    }

    if (!motor_apply_pair(0, 0, "initial stop")) {
        while (1) {
            usleep(250000);
        }
    }

    printf("\nStarting repeating polarity test loop...\n");
    printf("Observe wheel direction for each phase.\n");

    while (1) {
        printf("\n--- POSITIVE COMMAND PHASE ---\n");
        printf("Expected register effect: DUTY0=DUTY1=%d, DIR_MASK should show non-reverse state.\n",
               MOTOR_TEST_DUTY);
        if (!motor_apply_pair(MOTOR_TEST_DUTY, MOTOR_TEST_DUTY, "positive command")) {
            break;
        }
        usleep(RUN_TIME_US);

        printf("\n--- STOP PHASE ---\n");
        if (!motor_apply_pair(0, 0, "stop after positive")) {
            break;
        }
        usleep(STOP_TIME_US);

        printf("\n--- NEGATIVE COMMAND PHASE ---\n");
        printf("Expected register effect: DUTY0=DUTY1=%d, DIR_MASK should flip versus positive phase.\n",
               MOTOR_TEST_DUTY);
        if (!motor_apply_pair(-MOTOR_TEST_DUTY, -MOTOR_TEST_DUTY, "negative command")) {
            break;
        }
        usleep(RUN_TIME_US);

        printf("\n--- STOP PHASE ---\n");
        if (!motor_apply_pair(0, 0, "stop after negative")) {
            break;
        }
        usleep(STOP_TIME_US);
    }

    printf("\nTest ended due to error. Holding motors off.\n");
    (void)motor_apply_pair(0, 0, "final stop");

    while (1) {
        usleep(250000);
    }

    return 0;
}