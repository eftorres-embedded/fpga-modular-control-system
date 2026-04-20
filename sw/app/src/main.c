#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

#include "spi_regs.h"
#include "adxl345.h"
#include "pwm_regs.h"
#include "motor_pwm.h"

/*
 * Combined bring-up test:
 * 1) Initializes SPI + ADXL345
 * 2) Initializes LED PWM instance at LED_PWM_BASE
 * 3) Initializes motor PWM wrapper at MOTOR_PWM_BASE
 * 4) Leaves motors in a safe OFF state
 * 5) Continuously prints raw X/Y/Z and updates LED brightness pattern
 *
 * Expected baseline after adxl345_init_default():
 *   DATA_FORMAT = 0x00
 *   DEVID       = 0xE5
 *   BW_RATE     = 0x0A
 *   POWER_CTL   = 0x08
 */

#define LED_CHANNELS            4u
#define LED_PWM_PERIOD_DEFAULT  25000u
#define MOTOR_PWM_PERIOD_DEFAULT 25000u

static void print_reg_u8(const char *name, uint8_t reg)
{
    uint8_t value = 0u;
    adxl345_status_t st = adxl345_read_reg(reg, &value);

    if (st == ADXL345_OK) {
        printf("%s = 0x%02X\n", name, value);
    } else {
        printf("%s read failed, status = %d\n", name, (int)st);
    }
}

static void led_pwm_set_step(uint32_t step)
{
    uint32_t duty[LED_CHANNELS];
    uint32_t base;

    /* Simple moving-brightness pattern for LED PWM testing. */
    base    = (step % 5u) * 4000u;
    duty[0] = base;
    duty[1] = (base + 4000u) % LED_PWM_PERIOD_DEFAULT;
    duty[2] = (base + 8000u) % LED_PWM_PERIOD_DEFAULT;
    duty[3] = (base + 12000u) % LED_PWM_PERIOD_DEFAULT;

    (void)pwm_common_apply_frame(LED_PWM_BASE,
                                 LED_PWM_PERIOD_DEFAULT,
                                 duty,
                                 LED_CHANNELS,
                                 0x0Fu,
                                 true);
}

static void motor_safe_startup(void)
{
    motor_pwm_status_t mst;

    mst = motor_pwm_init(2u, MOTOR_PWM_PERIOD_DEFAULT);
    if (mst != MOTOR_PWM_OK) {
        printf("motor_pwm_init failed, status = %d\n", (int)mst);
        return;
    }

    /* Leave motors fully off at startup. */
    mst = motor_pwm_all_off();
    if (mst != MOTOR_PWM_OK) {
        printf("motor_pwm_all_off failed, status = %d\n", (int)mst);
    }
}

int main(void)
{
    adxl345_status_t st;
    adxl345_raw_xyz_t xyz;
    uint8_t devid = 0u;
    uint32_t led_step = 0u;

    printf("\nADXL345 + MOTOR PWM + LED PWM bring-up test\n");

    /* ---------------------------------------------------------------------
     * SPI + ADXL345
     * ------------------------------------------------------------------ */
    printf("Initializing SPI...\n");
    spi_init();

    printf("Running ADXL345 default init...\n");
    st = adxl345_init_default();
    if (st != ADXL345_OK) {
        printf("ADXL345 init failed, status = %d\n", (int)st);
        while (1) {
            usleep(250000);
        }
    }

    st = adxl345_read_device_id(&devid);
    if (st != ADXL345_OK) {
        printf("DEVID read failed, status = %d\n", (int)st);
        while (1) {
            usleep(250000);
        }
    }

    printf("\nInitial ADXL345 register readback:\n");
    print_reg_u8("DATA_FORMAT", ADXL345_REG_DATA_FORMAT);
    print_reg_u8("DEVID",       ADXL345_REG_DEVID);
    print_reg_u8("BW_RATE",     ADXL345_REG_BW_RATE);
    print_reg_u8("POWER_CTL",   ADXL345_REG_POWER_CTL);

    if (devid != ADXL345_DEVID_VALUE) {
        printf("Unexpected DEVID: got 0x%02X, expected 0x%02X\n",
               devid, ADXL345_DEVID_VALUE);
        while (1) {
            usleep(250000);
        }
    }

    /* ---------------------------------------------------------------------
     * LED PWM instance
     * ------------------------------------------------------------------ */
    printf("\nInitializing LED PWM at 0x%08X...\n", (unsigned)LED_PWM_BASE);
    led_pwm_set_step(0u);

    /* ---------------------------------------------------------------------
     * Motor PWM instance
     * ------------------------------------------------------------------ */
    printf("Initializing MOTOR PWM at 0x%08X...\n", (unsigned)MOTOR_PWM_BASE);
    motor_safe_startup();

    printf("Motors are left OFF for safe startup.\n");
    printf("\nStreaming raw X/Y/Z values and stepping LED PWM...\n");
    printf("(Ctrl+C / stop from debugger when done)\n\n");

    motor_pwm_set_signed(MOTOR_PWM_LEFT_CHANNEL,  2000);
    motor_pwm_set_signed(MOTOR_PWM_RIGHT_CHANNEL, 2000);
    motor_pwm_apply();

    while (1) {
        st = adxl345_read_xyz_raw(&xyz);
        if (st != ADXL345_OK) {
            printf("XYZ read failed, status = %d\n", (int)st);
        } else {
            printf("X=%6d  Y=%6d  Z=%6d\n",
                   (int)xyz.x,
                   (int)xyz.y,
                   (int)xyz.z);
        }

        led_pwm_set_step(led_step++);

        /* 10 Hz console update rate. */
        usleep(100000);
    }

    return 0;
}
