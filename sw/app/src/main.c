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
#include "seg7_debug_regs.h"
#include "gpio_regs.h"

/*
 * Combined bring-up / comparison test:
 * 1) Initializes SPI + ADXL345
 * 2) Initializes I2C + MPU-6500
 * 3) Initializes LED PWM at LED_PWM_BASE
 * 4) Initializes motor PWM at MOTOR_PWM_BASE
 * 5) Reads SW[9:0] through GPIO block
 * 6) Uses lower switch bits for motor control
 * 7) Uses upper switch bits to select 7-segment page
 */

#define LED_CHANNELS                10u
#define LED_PWM_PERIOD_DEFAULT      25000u
#define LED_PWM_ENABLE_MASK         ((1u << LED_CHANNELS) - 1u)

#define MOTOR_PWM_PERIOD_DEFAULT    25000u
#define I2C_DIVISOR_DEFAULT         250u
#define MOTOR_SMALL_DUTY            2000
#define STREAM_PERIOD_US            100000u

/* GPIO / switch map */
#define GPIO_SWITCH_MASK            0x03FFu

#define SW_COAST_BIT                0u
#define SW_HOLD_DUTY_BIT            1u
#define SW_ENABLE_SWEEP_BIT         2u

#define SW_SEG7_PAGE_SHIFT          7u
#define SW_SEG7_PAGE_MASK           0x7u

/* 7-seg page select from SW[9:7] */
#define SEG7_PAGE_I2C_GYRO          0u
#define SEG7_PAGE_I2C_ACCEL         1u
#define SEG7_PAGE_SPI_ACCEL         2u
#define SEG7_PAGE_I2C_TEMP          3u
#define SEG7_PAGE_LEFT_MOTOR_DUTY   4u
#define SEG7_PAGE_RIGHT_MOTOR_DUTY  5u

/* Motor sweep settings */
#define MOTOR_SWEEP_MIN_DUTY        1000
#define MOTOR_SWEEP_MAX_DUTY        8000
#define MOTOR_SWEEP_PERIOD_TICKS    80u   /* 80 * 100 ms = 8 s full triangle */

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
        return 256;
    }

    switch (range) {
    case 0u: return 256;
    case 1u: return 128;
    case 2u: return 64;
    default: return 32;
    }
}

static int32_t mpu6500_lsb_per_g_from_accel_config(uint8_t accel_config)
{
    switch ((accel_config >> 3) & 0x3u) {
    case 0u: return 16384;
    case 1u: return 8192;
    case 2u: return 4096;
    default: return 2048;
    }
}

static int32_t adxl345_full_scale_mg_from_data_format(uint8_t data_format)
{
    switch (data_format & 0x3u) {
    case 0u: return 2000;
    case 1u: return 4000;
    case 2u: return 8000;
    default: return 16000;
    }
}

static int32_t mpu6500_full_scale_mg_from_accel_config(uint8_t accel_config)
{
    switch ((accel_config >> 3) & 0x3u) {
    case 0u: return 2000;
    case 1u: return 4000;
    case 2u: return 8000;
    default: return 16000;
    }
}

static int32_t raw_to_milli_g(int16_t raw, int32_t lsb_per_g)
{
    return div_round_nearest_s32((int32_t)raw * 1000, lsb_per_g);
}

static int32_t mpu6500_temp_raw_to_centi_f(int16_t raw_temp)
{
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

static bool motor_init_idle(void)
{
    motor_pwm_status_t mst;

    mst = motor_pwm_init(2u, MOTOR_PWM_PERIOD_DEFAULT);
    if (mst != MOTOR_PWM_OK) {
        printf("motor_pwm_init failed, status = %d\n", (int)mst);
        return false;
    }

    mst = motor_pwm_set_signed(MOTOR_PWM_LEFT_CHANNEL, 0);
    if (mst != MOTOR_PWM_OK) {
        printf("left motor idle set failed, status = %d\n", (int)mst);
        return false;
    }

    mst = motor_pwm_set_signed(MOTOR_PWM_RIGHT_CHANNEL, 0);
    if (mst != MOTOR_PWM_OK) {
        printf("right motor idle set failed, status = %d\n", (int)mst);
        return false;
    }

    mst = motor_pwm_apply();
    if (mst != MOTOR_PWM_OK) {
        printf("motor_pwm_apply failed, status = %d\n", (int)mst);
        return false;
    }

    return true;
}

static bool motor_apply_signed_pair(int32_t left_duty, int32_t right_duty)
{
    motor_pwm_status_t mst;

    mst = motor_pwm_set_signed(MOTOR_PWM_LEFT_CHANNEL, left_duty);
    if (mst != MOTOR_PWM_OK) {
        printf("left motor set failed, status = %d\n", (int)mst);
        return false;
    }

    mst = motor_pwm_set_signed(MOTOR_PWM_RIGHT_CHANNEL, right_duty);
    if (mst != MOTOR_PWM_OK) {
        printf("right motor set failed, status = %d\n", (int)mst);
        return false;
    }

    mst = motor_pwm_apply();
    if (mst != MOTOR_PWM_OK) {
        printf("motor_pwm_apply failed, status = %d\n", (int)mst);
        return false;
    }

    return true;
}

static int8_t normalize_to_s8(int32_t value, int32_t full_scale_abs)
{
    int32_t q;

    if (full_scale_abs <= 0) {
        return 0;
    }

    q = div_round_nearest_s32(value * 127, full_scale_abs);

    if (q > 127) {
        q = 127;
    } else if (q < -128) {
        q = -128;
    }

    return (int8_t)q;
}

static uint32_t pack_u8x3(uint8_t b2, uint8_t b1, uint8_t b0)
{
    return seg7_pack_hex6((uint8_t)(b2 >> 4), (uint8_t)(b2 & 0x0Fu),
                          (uint8_t)(b1 >> 4), (uint8_t)(b1 & 0x0Fu),
                          (uint8_t)(b0 >> 4), (uint8_t)(b0 & 0x0Fu));
}

static uint32_t pack_u12x2(uint16_t hi12, uint16_t lo12)
{
    hi12 &= 0x0FFFu;
    lo12 &= 0x0FFFu;

    return seg7_pack_hex6((uint8_t)((hi12 >> 8) & 0x0Fu),
                          (uint8_t)((hi12 >> 4) & 0x0Fu),
                          (uint8_t)( hi12       & 0x0Fu),
                          (uint8_t)((lo12 >> 8) & 0x0Fu),
                          (uint8_t)((lo12 >> 4) & 0x0Fu),
                          (uint8_t)( lo12       & 0x0Fu));
}

static uint16_t saturate_abs_u12(int32_t value)
{
    int32_t mag = value;

    if (mag < 0) {
        mag = -mag;
    }

    if (mag > 0x0FFF) {
        mag = 0x0FFF;
    }

    return (uint16_t)mag;
}

static int32_t motor_sweep_duty(uint32_t tick)
{
    const uint32_t swing = (uint32_t)(MOTOR_SWEEP_MAX_DUTY - MOTOR_SWEEP_MIN_DUTY);
    const uint32_t frac  = triangle_0_to_1000(tick, MOTOR_SWEEP_PERIOD_TICKS);

    return (int32_t)(MOTOR_SWEEP_MIN_DUTY + ((swing * frac) / 1000u));
}

static void seg7_update_switch_page(uint32_t page,
                                    int16_t mpu_gx_raw,
                                    int16_t mpu_gy_raw,
                                    int16_t mpu_gz_raw,
                                    int32_t mpu_ax_mg,
                                    int32_t mpu_ay_mg,
                                    int32_t mpu_az_mg,
                                    int32_t adxl_x_mg,
                                    int32_t adxl_y_mg,
                                    int32_t adxl_z_mg,
                                    int32_t temp_f_centi,
                                    int32_t left_motor_duty_cmd,
                                    int32_t right_motor_duty_cmd,
                                    int32_t mpu_full_scale_mg,
                                    int32_t adxl_full_scale_mg)
{
    switch (page & SW_SEG7_PAGE_MASK) {
    case SEG7_PAGE_I2C_GYRO:
        seg7_set_mode(SEG7_MODE_SPLIT3X8);
        seg7_set_dp_n(0x3Fu);
        seg7_set_blank(0x00u);
        seg7_set_sw_value(
            pack_u8x3((uint8_t)normalize_to_s8((int32_t)mpu_gx_raw, 32767),
                      (uint8_t)normalize_to_s8((int32_t)mpu_gy_raw, 32767),
                      (uint8_t)normalize_to_s8((int32_t)mpu_gz_raw, 32767))
        );
        break;

    case SEG7_PAGE_I2C_ACCEL:
        seg7_set_mode(SEG7_MODE_SPLIT3X8);
        seg7_set_dp_n(0x3Fu);
        seg7_set_blank(0x00u);
        seg7_set_sw_value(
            pack_u8x3((uint8_t)normalize_to_s8(mpu_ax_mg, mpu_full_scale_mg),
                      (uint8_t)normalize_to_s8(mpu_ay_mg, mpu_full_scale_mg),
                      (uint8_t)normalize_to_s8(mpu_az_mg, mpu_full_scale_mg))
        );
        break;

    case SEG7_PAGE_SPI_ACCEL:
        seg7_set_mode(SEG7_MODE_SPLIT3X8);
        seg7_set_dp_n(0x3Fu);
        seg7_set_blank(0x00u);
        seg7_set_sw_value(
            pack_u8x3((uint8_t)normalize_to_s8(adxl_x_mg, adxl_full_scale_mg),
                      (uint8_t)normalize_to_s8(adxl_y_mg, adxl_full_scale_mg),
                      (uint8_t)normalize_to_s8(adxl_z_mg, adxl_full_scale_mg))
        );
        break;

    case SEG7_PAGE_I2C_TEMP:
        seg7_set_mode(SEG7_MODE_SPLIT2X12);
        seg7_set_dp_n(0x3Fu);
        seg7_set_blank(0x00u);
        seg7_set_sw_value(pack_u12x2(0u, saturate_abs_u12(temp_f_centi / 100)));
        break;

    case SEG7_PAGE_LEFT_MOTOR_DUTY:
        seg7_set_mode(SEG7_MODE_SPLIT2X12);
        seg7_set_dp_n(0x3Fu);
        seg7_set_blank(0x00u);
        seg7_set_sw_value(pack_u12x2(0u, saturate_abs_u12(left_motor_duty_cmd)));
        break;

    case SEG7_PAGE_RIGHT_MOTOR_DUTY:
        seg7_set_mode(SEG7_MODE_SPLIT2X12);
        seg7_set_dp_n(0x3Fu);
        seg7_set_blank(0x00u);
        seg7_set_sw_value(pack_u12x2(0u, saturate_abs_u12(right_motor_duty_cmd)));
        break;

    default:
        seg7_set_mode(SEG7_MODE_SPLIT3X8);
        seg7_set_dp_n(0x3Fu);
        seg7_set_blank(0x00u);
        seg7_set_sw_value(
            pack_u8x3((uint8_t)normalize_to_s8(mpu_ax_mg, mpu_full_scale_mg),
                      (uint8_t)normalize_to_s8(mpu_ay_mg, mpu_full_scale_mg),
                      (uint8_t)normalize_to_s8(mpu_az_mg, mpu_full_scale_mg))
        );
        break;
    }
}

int main(void)
{
    adxl345_status_t      adxl_st;
    mpu6500_status_t      mpu_st;
    adxl345_raw_xyz_t     adxl_xyz;
    mpu6500_raw_sample_t  mpu_sample;
    uint8_t               adxl_devid = 0u;
    uint8_t               adxl_data_format = 0u;
    uint8_t               mpu_whoami = 0u;
    uint8_t               mpu_accel_config = 0u;
    int32_t               adxl_lsb_per_g;
    int32_t               mpu_lsb_per_g;
    int32_t               adxl_full_scale_mg;
    int32_t               mpu_full_scale_mg;
    uint32_t              led_step = 0u;
    uint32_t              motor_tick = 0u;
    uint32_t              gpio_switch_word;
    uint32_t              switch_page;
    int32_t               left_motor_duty_cmd  = 0;
    int32_t               right_motor_duty_cmd = 0;
    bool                  motor_outputs_are_coasting = false;

    printf("\nADXL345 + MPU-6500 + MOTOR PWM + LED PWM + GPIO switch control test\n");

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

    adxl_lsb_per_g      = adxl345_lsb_per_g_from_data_format(adxl_data_format);
    mpu_lsb_per_g       = mpu6500_lsb_per_g_from_accel_config(mpu_accel_config);
    adxl_full_scale_mg  = adxl345_full_scale_mg_from_data_format(adxl_data_format);
    mpu_full_scale_mg   = mpu6500_full_scale_mg_from_accel_config(mpu_accel_config);

    printf("\nComputed accel scaling: ADXL=%ld LSB/g, MPU=%ld LSB/g\n",
           (long)adxl_lsb_per_g,
           (long)mpu_lsb_per_g);

    printf("Computed full-scale ranges: ADXL=+/- %ld mg, MPU=+/- %ld mg\n",
           (long)adxl_full_scale_mg,
           (long)mpu_full_scale_mg);

    printf("\nInitializing LED PWM at 0x%08X...\n", (unsigned)LED_PWM_BASE);
    led_pwm_set_step(0u);

    printf("Initializing MOTOR PWM at 0x%08X...\n", (unsigned)MOTOR_PWM_BASE);
    if (!motor_init_idle()) {
        while (1) {
            usleep(250000);
        }
    }

    printf("Initializing SEG7 DEBUG at 0x%08X...\n", (unsigned)SEG7_DEBUG_BASE);
    seg7_init();
    seg7_select_software();
    seg7_set_blank(0x00u);
    seg7_set_dp_n(0x3Fu);

    /*
     * GPIO mapping in top level:
     *   gpio[9:0]   = SW[9:0]
     *   gpio[11:10] = KEY[1:0]
     */
    set_tris(GPIO_BASE, 0xFFFFFFFFu);

    printf("\nSwitch control map:\n");
    printf("  SW[0]   = coast motors\n");
    printf("  SW[1]   = hold current duty\n");
    printf("  SW[2]   = enable duty sweep\n");
    printf("  SW[9:7] = 7-seg page select\n");
    printf("            0=i2c gyro, 1=i2c accel, 2=spi accel,\n");
    printf("            3=i2c temp, 4=left duty, 5=right duty\n");
    printf("(Ctrl+C / stop from debugger when done)\n\n");

    while (1) {
        bool coast_en;
        bool hold_en;
        bool sweep_en;
        int32_t next_left_motor_duty_cmd;
        int32_t next_right_motor_duty_cmd;

        gpio_switch_word = read_port(GPIO_BASE) & GPIO_SWITCH_MASK;
        switch_page      = (gpio_switch_word >> SW_SEG7_PAGE_SHIFT) & SW_SEG7_PAGE_MASK;

        coast_en = ((gpio_switch_word >> SW_COAST_BIT) & 1u) != 0u;
        hold_en  = ((gpio_switch_word >> SW_HOLD_DUTY_BIT) & 1u) != 0u;
        sweep_en = ((gpio_switch_word >> SW_ENABLE_SWEEP_BIT) & 1u) != 0u;

        adxl_st = adxl345_read_xyz_raw(&adxl_xyz);
        mpu_st  = mpu6500_read_all_raw(&mpu_sample);

        if (adxl_st != ADXL345_OK) {
            printf("ADXL345 read failed, status = %d\n", (int)adxl_st);
        }

        if (mpu_st != MPU6500_OK) {
            printf("MPU-6500 read failed, status = %d\n", (int)mpu_st);
        }

        next_left_motor_duty_cmd  = left_motor_duty_cmd;
        next_right_motor_duty_cmd = right_motor_duty_cmd;

        if (coast_en)
        {
            if (!motor_outputs_are_coasting)
            {
                (void)motor_pwm_coast_all();
                (void)motor_pwm_apply();
                motor_outputs_are_coasting = true;
            }
        }
        else
        {
            if (!hold_en)
            {
                if (sweep_en)
                {
                    int32_t sweep_duty = motor_sweep_duty(motor_tick);

                    next_left_motor_duty_cmd  = sweep_duty;
                    next_right_motor_duty_cmd = sweep_duty;
                }
                else
                {
                    next_left_motor_duty_cmd  = MOTOR_SMALL_DUTY;
                    next_right_motor_duty_cmd = MOTOR_SMALL_DUTY;
                }
            }

            if (motor_outputs_are_coasting ||
                (next_left_motor_duty_cmd  != left_motor_duty_cmd) ||
                (next_right_motor_duty_cmd != right_motor_duty_cmd))
            {
                (void)motor_apply_signed_pair(next_left_motor_duty_cmd,
                                              next_right_motor_duty_cmd);

                left_motor_duty_cmd        = next_left_motor_duty_cmd;
                right_motor_duty_cmd       = next_right_motor_duty_cmd;
                motor_outputs_are_coasting = false;
            }
        }

        if ((adxl_st == ADXL345_OK) && (mpu_st == MPU6500_OK)) {
            const int32_t adxl_x_mg    = raw_to_milli_g(adxl_xyz.x, adxl_lsb_per_g);
            const int32_t adxl_y_mg    = raw_to_milli_g(adxl_xyz.y, adxl_lsb_per_g);
            const int32_t adxl_z_mg    = raw_to_milli_g(adxl_xyz.z, adxl_lsb_per_g);

            const int32_t mpu_ax_mg    = raw_to_milli_g(mpu_sample.accel.x, mpu_lsb_per_g);
            const int32_t mpu_ay_mg    = raw_to_milli_g(mpu_sample.accel.y, mpu_lsb_per_g);
            const int32_t mpu_az_mg    = raw_to_milli_g(mpu_sample.accel.z, mpu_lsb_per_g);

            const int32_t temp_f_centi = mpu6500_temp_raw_to_centi_f(mpu_sample.temp);

            printf("SW=0x%03lX ", (unsigned long)gpio_switch_word);

            printf("ADXL[g]");
            print_signed_milli(" X=", adxl_x_mg, "");
            print_signed_milli(" Y=", adxl_y_mg, "");
            print_signed_milli(" Z=", adxl_z_mg, "");

            printf("   MPU_A[g]");
            print_signed_milli(" X=", mpu_ax_mg, "");
            print_signed_milli(" Y=", mpu_ay_mg, "");
            print_signed_milli(" Z=", mpu_az_mg, "");

            print_signed_centi("   MPU_T=", temp_f_centi, "F");

            printf("   MPU_G[raw] X=%6d Y=%6d Z=%6d",
                   (int)mpu_sample.gyro.x,
                   (int)mpu_sample.gyro.y,
                   (int)mpu_sample.gyro.z);

            printf("   duty[L,R]=[%ld,%ld]\n",
                   (long)left_motor_duty_cmd,
                   (long)right_motor_duty_cmd);

            seg7_update_switch_page(
                switch_page,
                mpu_sample.gyro.x,
                mpu_sample.gyro.y,
                mpu_sample.gyro.z,
                mpu_ax_mg,
                mpu_ay_mg,
                mpu_az_mg,
                adxl_x_mg,
                adxl_y_mg,
                adxl_z_mg,
                temp_f_centi,
                left_motor_duty_cmd,
                right_motor_duty_cmd,
                mpu_full_scale_mg,
                adxl_full_scale_mg
            );
        }

        led_pwm_set_step(led_step++);
        motor_tick++;
        usleep(STREAM_PERIOD_US);
    }

    return 0;
}