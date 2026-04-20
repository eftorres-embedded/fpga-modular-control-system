#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>

#include "spi_regs.h"
#include "adxl345.h"
#include "i2c_regs.h"
#include "mpu6500.h"
#include "pwm_regs.h"
#include "motor_pwm.h"

/*
 * Combined bring-up / comparison test:
 * 1) Initializes SPI + ADXL345
 * 2) Initializes I2C + MPU-6500
 * 3) Initializes LED PWM at LED_PWM_BASE
 * 4) Initializes motor PWM at MOTOR_PWM_BASE
 * 5) Starts both motors at a small duty cycle
 * 6) Continuously prints both IMUs so their values can be compared live
 *
 * Updates in this revision:
 * - ADXL345 and MPU-6500 accelerometer data are printed in g units.
 * - MPU-6500 temperature is printed in degrees Fahrenheit.
 * - LED animation now drives 10 PWM channels with a smoother "comet + breathe"
 *   effect that looks nicer on the DE10-Lite LED bank.
 *
 * Notes:
 * - Float printf support is intentionally avoided. Everything is printed with
 *   fixed-point integer formatting so this stays lightweight and linker-safe.
 * - Accel scaling is derived from the sensor configuration registers, so if you
 *   change range settings later, the printed g values still track correctly.
 */

#define LED_CHANNELS                10u
#define LED_PWM_PERIOD_DEFAULT      25000u
#define LED_PWM_ENABLE_MASK         ((1u << LED_CHANNELS) - 1u)
#define MOTOR_PWM_PERIOD_DEFAULT    25000u
#define I2C_DIVISOR_DEFAULT         250u
#define MOTOR_SMALL_DUTY            2000
#define STREAM_PERIOD_US            100000u

static void print_adxl_reg_u8(const char *name, uint8_t reg)
{
    uint8_t value = 0u;
    adxl345_status_t st = adxl345_read_reg(reg, &value);

    if (st == ADXL345_OK) {
        printf("ADXL %-12s = 0x%02X\n", name, value);
    } else {
        printf("ADXL %-12s read failed, status = %d\n", name, (int)st);
    }
}

static void print_mpu_reg_u8(const char *name, uint8_t reg)
{
    uint8_t value = 0u;
    mpu6500_status_t st = mpu6500_read_reg(reg, &value);

    if (st == MPU6500_OK) {
        printf("MPU  %-12s = 0x%02X\n", name, value);
    } else {
        printf("MPU  %-12s read failed, status = %d\n", name, (int)st);
    }
}

static int32_t div_round_nearest_s32(int32_t numer, int32_t denom)
{
    if (denom <= 0) {
        return 0;
    }

    if (numer >= 0) {
        return (numer + (denom / 2)) / denom;
    }

    return -(((-numer) + (denom / 2)) / denom);
}

static int32_t adxl345_lsb_per_g_from_data_format(uint8_t data_format)
{
    const bool full_res = ((data_format >> 3) & 0x1u) != 0u;
    const uint8_t range = data_format & 0x3u;

    if (full_res) {
        return 256;   /* 3.9 mg/LSB nominal for all ranges */
    }

    switch (range) {
    case 0u: return 256; /* +/-2 g */
    case 1u: return 128; /* +/-4 g */
    case 2u: return 64;  /* +/-8 g */
    default: return 32;  /* +/-16 g */
    }
}

static int32_t mpu6500_lsb_per_g_from_accel_config(uint8_t accel_config)
{
    switch ((accel_config >> 3) & 0x3u) {
    case 0u: return 16384; /* +/-2 g */
    case 1u: return 8192;  /* +/-4 g */
    case 2u: return 4096;  /* +/-8 g */
    default: return 2048;  /* +/-16 g */
    }
}

static int32_t raw_to_milli_g(int16_t raw, int32_t lsb_per_g)
{
    return div_round_nearest_s32((int32_t)raw * 1000, lsb_per_g);
}

static int32_t mpu6500_temp_raw_to_centi_f(int16_t raw_temp)
{
    /*
     * MPU-6500 temperature conversion:
     *   Temp_C = 21 + raw / 333.87
     *   Temp_F = Temp_C * 9/5 + 32
     *
     * Fixed-point implementation in centi-degrees Fahrenheit.
     */
    const int32_t temp_c_centi = 2100 + div_round_nearest_s32((int32_t)raw_temp * 100, 33387);
    return 3200 + div_round_nearest_s32(temp_c_centi * 9, 5);
}

static void print_signed_milli(const char *prefix, int32_t milli, const char *suffix)
{
    int32_t mag = milli;

    if (mag < 0) {
        mag = -mag;
        printf("%s-%ld.%03ld%s", prefix, (long)(mag / 1000), (long)(mag % 1000), suffix);
    } else {
        printf("%s+%ld.%03ld%s", prefix, (long)(mag / 1000), (long)(mag % 1000), suffix);
    }
}

static void print_signed_centi(const char *prefix, int32_t centi, const char *suffix)
{
    int32_t mag = centi;

    if (mag < 0) {
        mag = -mag;
        printf("%s-%ld.%02ld%s", prefix, (long)(mag / 100), (long)(mag % 100), suffix);
    } else {
        printf("%s%ld.%02ld%s", prefix, (long)(mag / 100), (long)(mag % 100), suffix);
    }
}

static uint32_t triangle_0_to_1000(uint32_t phase, uint32_t period)
{
    uint32_t half;
    uint32_t x;

    if (period < 2u) {
        return 0u;
    }

    x    = phase % period;
    half = period / 2u;

    if (x < half) {
        return (1000u * x) / half;
    }

    return (1000u * (period - 1u - x)) / (period - half);
}

static uint32_t ping_pong_index(uint32_t step, uint32_t count)
{
    uint32_t span;
    uint32_t x;

    if (count <= 1u) {
        return 0u;
    }

    span = 2u * (count - 1u);
    x    = step % span;

    if (x < count) {
        return x;
    }

    return span - x;
}

static uint32_t led_tail_level(uint32_t dist)
{
    switch (dist) {
    case 0u: return 1000u;
    case 1u: return 550u;
    case 2u: return 220u;
    case 3u: return 80u;
    case 4u: return 25u;
    default: return 0u;
    }
}

static void led_pwm_set_step(uint32_t step)
{
    uint32_t duty[LED_CHANNELS];
    uint32_t head_a;
    uint32_t head_b;
    uint32_t breathe;
    uint32_t i;

    head_a  = ping_pong_index(step, LED_CHANNELS);
    head_b  = ping_pong_index((step / 2u) + (LED_CHANNELS - 1u), LED_CHANNELS);
    breathe = triangle_0_to_1000(step, 64u);

    for (i = 0u; i < LED_CHANNELS; ++i) {
        uint32_t dist_a = (i > head_a) ? (i - head_a) : (head_a - i);
        uint32_t dist_b = (i > head_b) ? (i - head_b) : (head_b - i);
        uint32_t ambient = 30u + ((breathe * (25u + (i * 3u))) / 1000u);
        uint32_t sparkle = triangle_0_to_1000((step * 3u) + (i * 7u), 48u) / 20u;
        uint32_t level = ambient + led_tail_level(dist_a) + (led_tail_level(dist_b) / 2u) + sparkle;

        if (level > 1000u) {
            level = 1000u;
        }

        duty[i] = (level * (LED_PWM_PERIOD_DEFAULT - 1u)) / 1000u;
    }

    (void)pwm_common_apply_frame(LED_PWM_BASE,
                                 LED_PWM_PERIOD_DEFAULT,
                                 duty,
                                 LED_CHANNELS,
                                 LED_PWM_ENABLE_MASK,
                                 true);
}

static void motor_start_small_forward(void)
{
    motor_pwm_status_t mst;

    mst = motor_pwm_init(2u, MOTOR_PWM_PERIOD_DEFAULT);
    if (mst != MOTOR_PWM_OK) {
        printf("motor_pwm_init failed, status = %d\n", (int)mst);
        return;
    }

    mst = motor_pwm_set_signed(MOTOR_PWM_LEFT_CHANNEL, MOTOR_SMALL_DUTY);
    if (mst != MOTOR_PWM_OK) {
        printf("left motor set failed, status = %d\n", (int)mst);
        return;
    }

    mst = motor_pwm_set_signed(MOTOR_PWM_RIGHT_CHANNEL, MOTOR_SMALL_DUTY);
    if (mst != MOTOR_PWM_OK) {
        printf("right motor set failed, status = %d\n", (int)mst);
        return;
    }

    mst = motor_pwm_apply();
    if (mst != MOTOR_PWM_OK) {
        printf("motor_pwm_apply failed, status = %d\n", (int)mst);
    }
}

int main(void)
{
    adxl345_status_t adxl_st;
    mpu6500_status_t mpu_st;
    adxl345_raw_xyz_t adxl_xyz;
    mpu6500_raw_sample_t mpu_sample;
    uint8_t adxl_devid = 0u;
    uint8_t adxl_data_format = 0u;
    uint8_t mpu_whoami = 0u;
    uint8_t mpu_accel_config = 0u;
    int32_t adxl_lsb_per_g;
    int32_t mpu_lsb_per_g;
    uint32_t led_step = 0u;

    printf("\nADXL345 + MPU-6500 + MOTOR PWM + LED PWM bring-up test\n");

    /* ---------------------------------------------------------------------
     * SPI + ADXL345
     * ------------------------------------------------------------------ */
    printf("Initializing SPI...\n");
    spi_init();

    printf("Running ADXL345 default init...\n");
    adxl_st = adxl345_init_default();
    if (adxl_st != ADXL345_OK) {
        printf("ADXL345 init failed, status = %d\n", (int)adxl_st);
        while (1) {
            usleep(250000);
        }
    }

    adxl_st = adxl345_read_device_id(&adxl_devid);
    if (adxl_st != ADXL345_OK) {
        printf("ADXL345 DEVID read failed, status = %d\n", (int)adxl_st);
        while (1) {
            usleep(250000);
        }
    }

    adxl_st = adxl345_read_reg(ADXL345_REG_DATA_FORMAT, &adxl_data_format);
    if (adxl_st != ADXL345_OK) {
        printf("ADXL345 DATA_FORMAT read failed, status = %d\n", (int)adxl_st);
        while (1) {
            usleep(250000);
        }
    }

    /* ---------------------------------------------------------------------
     * I2C + MPU-6500
     * ------------------------------------------------------------------ */
    printf("Initializing I2C...\n");
    i2c_init(I2C_DIVISOR_DEFAULT);

    printf("Running MPU-6500 default init...\n");
    mpu_st = mpu6500_init_default();
    if (mpu_st != MPU6500_OK) {
        printf("MPU-6500 init failed, status = %d\n", (int)mpu_st);
        while (1) {
            usleep(250000);
        }
    }

    mpu_st = mpu6500_read_whoami(&mpu_whoami);
    if (mpu_st != MPU6500_OK) {
        printf("MPU-6500 WHO_AM_I read failed, status = %d\n", (int)mpu_st);
        while (1) {
            usleep(250000);
        }
    }

    mpu_st = mpu6500_read_reg(MPU6500_REG_ACCEL_CONFIG, &mpu_accel_config);
    if (mpu_st != MPU6500_OK) {
        printf("MPU-6500 ACCEL_CONFIG read failed, status = %d\n", (int)mpu_st);
        while (1) {
            usleep(250000);
        }
    }

    printf("\nInitial register readback:\n");
    print_adxl_reg_u8("DATA_FORMAT", ADXL345_REG_DATA_FORMAT);
    print_adxl_reg_u8("DEVID",       ADXL345_REG_DEVID);
    print_adxl_reg_u8("BW_RATE",     ADXL345_REG_BW_RATE);
    print_adxl_reg_u8("POWER_CTL",   ADXL345_REG_POWER_CTL);

    print_mpu_reg_u8("WHO_AM_I",      MPU6500_REG_WHO_AM_I);
    print_mpu_reg_u8("PWR_MGMT_1",    MPU6500_REG_PWR_MGMT_1);
    print_mpu_reg_u8("SMPLRT_DIV",    MPU6500_REG_SMPLRT_DIV);
    print_mpu_reg_u8("CONFIG",        MPU6500_REG_CONFIG);
    print_mpu_reg_u8("GYRO_CONFIG",   MPU6500_REG_GYRO_CONFIG);
    print_mpu_reg_u8("ACCEL_CONFIG",  MPU6500_REG_ACCEL_CONFIG);
    print_mpu_reg_u8("ACCEL_CONFIG2", MPU6500_REG_ACCEL_CONFIG2);

    if (adxl_devid != ADXL345_DEVID_VALUE) {
        printf("Unexpected ADXL345 DEVID: got 0x%02X, expected 0x%02X\n",
               adxl_devid, ADXL345_DEVID_VALUE);
        while (1) {
            usleep(250000);
        }
    }

    if (mpu_whoami != MPU6500_WHO_AM_I_VALUE) {
        printf("Unexpected MPU-6500 WHO_AM_I: got 0x%02X, expected 0x%02X\n",
               mpu_whoami, MPU6500_WHO_AM_I_VALUE);
        while (1) {
            usleep(250000);
        }
    }

    adxl_lsb_per_g = adxl345_lsb_per_g_from_data_format(adxl_data_format);
    mpu_lsb_per_g  = mpu6500_lsb_per_g_from_accel_config(mpu_accel_config);

    printf("\nComputed accel scaling: ADXL=%ld LSB/g, MPU=%ld LSB/g\n",
           (long)adxl_lsb_per_g,
           (long)mpu_lsb_per_g);

    /* ---------------------------------------------------------------------
     * LED PWM instance
     * ------------------------------------------------------------------ */
    printf("\nInitializing LED PWM at 0x%08X...\n", (unsigned)LED_PWM_BASE);
    led_pwm_set_step(0u);

    /* ---------------------------------------------------------------------
     * Motor PWM instance
     * ------------------------------------------------------------------ */
    printf("Initializing MOTOR PWM at 0x%08X...\n", (unsigned)MOTOR_PWM_BASE);
    motor_start_small_forward();

    printf("Motors commanded forward at small duty = %d\n", MOTOR_SMALL_DUTY);
    printf("\nStreaming both IMUs with accel in g and MPU temp in F...\n");
    printf("(Ctrl+C / stop from debugger when done)\n\n");

    while (1) {
        adxl_st = adxl345_read_xyz_raw(&adxl_xyz);
        mpu_st  = mpu6500_read_all_raw(&mpu_sample);

        if (adxl_st != ADXL345_OK) {
            printf("ADXL345 read failed, status = %d\n", (int)adxl_st);
        }

        if (mpu_st != MPU6500_OK) {
            printf("MPU-6500 read failed, status = %d\n", (int)mpu_st);
        }

        if ((adxl_st == ADXL345_OK) && (mpu_st == MPU6500_OK)) {
            const int32_t adxl_x_mg = raw_to_milli_g(adxl_xyz.x, adxl_lsb_per_g);
            const int32_t adxl_y_mg = raw_to_milli_g(adxl_xyz.y, adxl_lsb_per_g);
            const int32_t adxl_z_mg = raw_to_milli_g(adxl_xyz.z, adxl_lsb_per_g);

            const int32_t mpu_ax_mg = raw_to_milli_g(mpu_sample.accel.x, mpu_lsb_per_g);
            const int32_t mpu_ay_mg = raw_to_milli_g(mpu_sample.accel.y, mpu_lsb_per_g);
            const int32_t mpu_az_mg = raw_to_milli_g(mpu_sample.accel.z, mpu_lsb_per_g);

            const int32_t temp_f_centi = mpu6500_temp_raw_to_centi_f(mpu_sample.temp);

            printf("ADXL[g]");
            print_signed_milli(" X=", adxl_x_mg, "");
            print_signed_milli(" Y=", adxl_y_mg, "");
            print_signed_milli(" Z=", adxl_z_mg, "");

            printf("   MPU_A[g]");
            print_signed_milli(" X=", mpu_ax_mg, "");
            print_signed_milli(" Y=", mpu_ay_mg, "");
            print_signed_milli(" Z=", mpu_az_mg, "");

            print_signed_centi("   MPU_T=", temp_f_centi, "F");

            printf("   MPU_G[raw] X=%6d Y=%6d Z=%6d\n",
                   (int)mpu_sample.gyro.x,
                   (int)mpu_sample.gyro.y,
                   (int)mpu_sample.gyro.z);
        }

        led_pwm_set_step(led_step++);
        usleep(STREAM_PERIOD_US);
    }

    return 0;
}
