#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

#include "system.h"
#include "io.h"

#ifndef I2C_MASTER_0_BASE
#define I2C_MASTER_0_BASE 0x00034000u
#endif

#define I2C_BASE            I2C_MASTER_0_BASE

// i2c_regs register map
#define REG_STATUS          0x00u
#define REG_DIVISOR         0x04u
#define REG_TXDATA          0x08u
#define REG_RXDATA          0x0Cu
#define REG_CMD             0x10u

// REG_STATUS bit positions
#define ST_CMD_READY        0
#define ST_BUS_IDLE         1
#define ST_DONE_TICK        2
#define ST_ACK_VALID        3
#define ST_ACK              4
#define ST_RD_DATA_VALID    5
#define ST_CMD_ILLEGAL      6
#define ST_MASTER_RX        7

// Command encodings
#define START_CMD           0u
#define WR_CMD              1u
#define RD_CMD              2u
#define STOP_CMD            3u
#define RESTART_CMD         4u

// MPU-6500 registers
#define MPU6500_ADDR_7BIT       0x68u   // change to 0x69 if AD0 is high
#define MPU6500_WHO_AM_I_REG    0x75u
#define MPU6500_WHO_AM_I_EXP    0x70u

#define MPU6500_SMPLRT_DIV      0x19u
#define MPU6500_CONFIG          0x1Au
#define MPU6500_GYRO_CONFIG     0x1Bu
#define MPU6500_ACCEL_CONFIG    0x1Cu
#define MPU6500_ACCEL_CONFIG_2  0x1Du
#define MPU6500_INT_ENABLE      0x38u
#define MPU6500_ACCEL_XOUT_H    0x3Bu
#define MPU6500_TEMP_OUT_H      0x41u
#define MPU6500_GYRO_XOUT_H     0x43u
#define MPU6500_PWR_MGMT_1      0x6Bu
#define MPU6500_PWR_MGMT_2      0x6Cu

#define I2C_TIMEOUT_CYCLES      1000000u
#define GYRO_CAL_SAMPLES        1000u
#define GYRO_CAL_DELAY_US       2000u
#define STREAM_DELAY_US         100000u

// Full-scale settings used in this file:
// accel = +/-2 g, gyro = +/-250 dps
#define ACCEL_LSB_PER_G         16384.0f
#define GYRO_LSB_PER_DPS        131.0f

typedef struct {
    int16_t ax;
    int16_t ay;
    int16_t az;
    int16_t temp;
    int16_t gx;
    int16_t gy;
    int16_t gz;
} mpu6500_sample_t;

typedef struct {
    float gx_bias;
    float gy_bias;
    float gz_bias;
} gyro_bias_t;

static inline void i2c_wr32(uint32_t off, uint32_t val)
{
    IOWR_32DIRECT(I2C_BASE, off, val);
}

static inline uint32_t i2c_rd32(uint32_t off)
{
    return IORD_32DIRECT(I2C_BASE, off);
}

static int i2c_wait_cmd_ready(uint32_t timeout)
{
    while (timeout--) {
        uint32_t status = i2c_rd32(REG_STATUS);
        if ((status >> ST_CMD_READY) & 0x1u) {
            return 0;
        }
    }
    return -1;
}

static int i2c_wait_bus_idle(uint32_t timeout)
{
    while (timeout--) {
        uint32_t status = i2c_rd32(REG_STATUS);
        if (((status >> ST_CMD_READY) & 0x1u) && ((status >> ST_BUS_IDLE) & 0x1u)) {
            return 0;
        }
    }
    return -1;
}

static int i2c_issue_cmd(uint32_t cmd, uint32_t rd_last)
{
    uint32_t cmd_word = (cmd & 0x7u) | ((rd_last & 0x1u) << 8);
    i2c_wr32(REG_CMD, cmd_word);
    return i2c_wait_cmd_ready(I2C_TIMEOUT_CYCLES);
}

static int i2c_write_byte_checked(uint8_t byte)
{
    uint32_t status;

    i2c_wr32(REG_TXDATA, (uint32_t)byte);

    if (i2c_issue_cmd(WR_CMD, 0u) != 0) {
        return -1;
    }

    status = i2c_rd32(REG_STATUS);

    // ACK = 0 means the slave acknowledged the byte
    if (((status >> ST_ACK) & 0x1u) != 0u) {
        return -2;
    }

    if (((status >> ST_CMD_ILLEGAL) & 0x1u) != 0u) {
        return -3;
    }

    return 0;
}

static int i2c_read_byte_last(uint8_t *byte_out)
{
    if (i2c_issue_cmd(RD_CMD, 1u) != 0) {
        return -1;
    }

    *byte_out = (uint8_t)(i2c_rd32(REG_RXDATA) & 0xFFu);
    return 0;
}

static int i2c_read_reg8(uint8_t dev_addr_7b, uint8_t reg_addr, uint8_t *value)
{
    int rc;

    rc = i2c_wait_bus_idle(I2C_TIMEOUT_CYCLES);
    if (rc != 0) {
        return -10;
    }

    rc = i2c_issue_cmd(START_CMD, 0u);
    if (rc != 0) {
        return -11;
    }

    rc = i2c_write_byte_checked((uint8_t)((dev_addr_7b << 1) | 0u));
    if (rc != 0) {
        (void)i2c_issue_cmd(STOP_CMD, 0u);
        return -12;
    }

    rc = i2c_write_byte_checked(reg_addr);
    if (rc != 0) {
        (void)i2c_issue_cmd(STOP_CMD, 0u);
        return -13;
    }

    rc = i2c_issue_cmd(RESTART_CMD, 0u);
    if (rc != 0) {
        (void)i2c_issue_cmd(STOP_CMD, 0u);
        return -14;
    }

    rc = i2c_write_byte_checked((uint8_t)((dev_addr_7b << 1) | 1u));
    if (rc != 0) {
        (void)i2c_issue_cmd(STOP_CMD, 0u);
        return -15;
    }

    rc = i2c_read_byte_last(value);
    if (rc != 0) {
        (void)i2c_issue_cmd(STOP_CMD, 0u);
        return -16;
    }

    rc = i2c_issue_cmd(STOP_CMD, 0u);
    if (rc != 0) {
        return -17;
    }

    return 0;
}

static int i2c_write_reg8(uint8_t dev_addr_7b, uint8_t reg_addr, uint8_t value)
{
    int rc;

    rc = i2c_wait_bus_idle(I2C_TIMEOUT_CYCLES);
    if (rc != 0) {
        return -20;
    }

    rc = i2c_issue_cmd(START_CMD, 0u);
    if (rc != 0) {
        return -21;
    }

    rc = i2c_write_byte_checked((uint8_t)((dev_addr_7b << 1) | 0u));
    if (rc != 0) {
        (void)i2c_issue_cmd(STOP_CMD, 0u);
        return -22;
    }

    rc = i2c_write_byte_checked(reg_addr);
    if (rc != 0) {
        (void)i2c_issue_cmd(STOP_CMD, 0u);
        return -23;
    }

    rc = i2c_write_byte_checked(value);
    if (rc != 0) {
        (void)i2c_issue_cmd(STOP_CMD, 0u);
        return -24;
    }

    rc = i2c_issue_cmd(STOP_CMD, 0u);
    if (rc != 0) {
        return -25;
    }

    return 0;
}

static int mpu6500_read_reg(uint8_t reg_addr, uint8_t *value)
{
    return i2c_read_reg8(MPU6500_ADDR_7BIT, reg_addr, value);
}

static int mpu6500_write_reg(uint8_t reg_addr, uint8_t value)
{
    return i2c_write_reg8(MPU6500_ADDR_7BIT, reg_addr, value);
}

static int mpu6500_read_s16_be(uint8_t reg_hi, int16_t *value)
{
    uint8_t hi;
    uint8_t lo;
    int rc;

    rc = mpu6500_read_reg(reg_hi, &hi);
    if (rc != 0) {
        return rc;
    }

    rc = mpu6500_read_reg((uint8_t)(reg_hi + 1u), &lo);
    if (rc != 0) {
        return rc;
    }

    *value = (int16_t)((((uint16_t)hi) << 8) | (uint16_t)lo);
    return 0;
}

static int mpu6500_read_sample(mpu6500_sample_t *s)
{
    int rc;

    rc = mpu6500_read_s16_be(MPU6500_ACCEL_XOUT_H + 0u, &s->ax);
    if (rc != 0) return rc;

    rc = mpu6500_read_s16_be(MPU6500_ACCEL_XOUT_H + 2u, &s->ay);
    if (rc != 0) return rc;

    rc = mpu6500_read_s16_be(MPU6500_ACCEL_XOUT_H + 4u, &s->az);
    if (rc != 0) return rc;

    rc = mpu6500_read_s16_be(MPU6500_TEMP_OUT_H, &s->temp);
    if (rc != 0) return rc;

    rc = mpu6500_read_s16_be(MPU6500_GYRO_XOUT_H + 0u, &s->gx);
    if (rc != 0) return rc;

    rc = mpu6500_read_s16_be(MPU6500_GYRO_XOUT_H + 2u, &s->gy);
    if (rc != 0) return rc;

    rc = mpu6500_read_s16_be(MPU6500_GYRO_XOUT_H + 4u, &s->gz);
    if (rc != 0) return rc;

    return 0;
}

static float accel_raw_to_g(int16_t raw)
{
    return ((float)raw) / ACCEL_LSB_PER_G;
}

static float gyro_raw_to_dps(float raw_minus_bias)
{
    return raw_minus_bias / GYRO_LSB_PER_DPS;
}

static float temp_raw_to_c(int16_t raw)
{
    return (((float)raw) / 333.87f) + 21.0f;
}

static int mpu6500_init(void)
{
    uint8_t who_am_i = 0u;
    uint8_t pwr_mgmt_1 = 0u;
    int rc;

    rc = mpu6500_read_reg(MPU6500_WHO_AM_I_REG, &who_am_i);
    if (rc != 0) {
        printf("WHO_AM_I pre-read failed rc=%d\n", rc);
        return -100;
    }

    printf("WHO_AM_I before init: 0x%02X\n", who_am_i);
    if (who_am_i != MPU6500_WHO_AM_I_EXP) {
        printf("WARNING: expected 0x%02X\n", MPU6500_WHO_AM_I_EXP);
    }

    rc = mpu6500_read_reg(MPU6500_PWR_MGMT_1, &pwr_mgmt_1);
    if (rc != 0) {
        printf("PWR_MGMT_1 pre-read failed rc=%d\n", rc);
        return -101;
    }
    printf("PWR_MGMT_1 before wake: 0x%02X\n", pwr_mgmt_1);

    rc = mpu6500_write_reg(MPU6500_PWR_MGMT_1, 0x00u);
    if (rc != 0) {
        printf("Write PWR_MGMT_1 failed rc=%d\n", rc);
        return -102;
    }

    usleep(100000);

    rc = mpu6500_read_reg(MPU6500_PWR_MGMT_1, &pwr_mgmt_1);
    if (rc != 0) {
        printf("PWR_MGMT_1 post-read failed rc=%d\n", rc);
        return -103;
    }
    printf("PWR_MGMT_1 after wake : 0x%02X\n", pwr_mgmt_1);

    rc = mpu6500_write_reg(MPU6500_PWR_MGMT_2, 0x00u);
    if (rc != 0) {
        printf("Write PWR_MGMT_2 failed rc=%d\n", rc);
        return -104;
    }

    rc = mpu6500_write_reg(MPU6500_SMPLRT_DIV, 0x07u);
    if (rc != 0) {
        printf("Write SMPLRT_DIV failed rc=%d\n", rc);
        return -105;
    }

    rc = mpu6500_write_reg(MPU6500_CONFIG, 0x01u);
    if (rc != 0) {
        printf("Write CONFIG failed rc=%d\n", rc);
        return -106;
    }

    rc = mpu6500_write_reg(MPU6500_GYRO_CONFIG, 0x00u);
    if (rc != 0) {
        printf("Write GYRO_CONFIG failed rc=%d\n", rc);
        return -107;
    }

    rc = mpu6500_write_reg(MPU6500_ACCEL_CONFIG, 0x00u);
    if (rc != 0) {
        printf("Write ACCEL_CONFIG failed rc=%d\n", rc);
        return -108;
    }

    rc = mpu6500_write_reg(MPU6500_ACCEL_CONFIG_2, 0x01u);
    if (rc != 0) {
        printf("Write ACCEL_CONFIG_2 failed rc=%d\n", rc);
        return -109;
    }

    rc = mpu6500_write_reg(MPU6500_INT_ENABLE, 0x00u);
    if (rc != 0) {
        printf("Write INT_ENABLE failed rc=%d\n", rc);
        return -110;
    }

    return 0;
}

static int mpu6500_calibrate_gyro(gyro_bias_t *bias)
{
    uint32_t i;
    int rc;
    int64_t gx_sum = 0;
    int64_t gy_sum = 0;
    int64_t gz_sum = 0;
    mpu6500_sample_t s;

    bias->gx_bias = 0.0f;
    bias->gy_bias = 0.0f;
    bias->gz_bias = 0.0f;

    printf("\nGyro calibration starting. Keep the board still...\n");

    for (i = 0; i < GYRO_CAL_SAMPLES; i++) {
        rc = mpu6500_read_sample(&s);
        if (rc != 0) {
            printf("Gyro calibration read failed rc=%d at sample %lu\n",
                   rc, (unsigned long)i);
            return -200;
        }

        gx_sum += s.gx;
        gy_sum += s.gy;
        gz_sum += s.gz;

        if ((i % 100u) == 0u) {
            printf("  cal sample %4lu / %4u\n",
                   (unsigned long)i, (unsigned)GYRO_CAL_SAMPLES);
        }

        usleep(GYRO_CAL_DELAY_US);
    }

    bias->gx_bias = (float)gx_sum / (float)GYRO_CAL_SAMPLES;
    bias->gy_bias = (float)gy_sum / (float)GYRO_CAL_SAMPLES;
    bias->gz_bias = (float)gz_sum / (float)GYRO_CAL_SAMPLES;

    printf("Gyro bias complete:\n");
    printf("  gx_bias = %.3f counts (%.3f dps)\n",
           bias->gx_bias, gyro_raw_to_dps(bias->gx_bias));
    printf("  gy_bias = %.3f counts (%.3f dps)\n",
           bias->gy_bias, gyro_raw_to_dps(bias->gy_bias));
    printf("  gz_bias = %.3f counts (%.3f dps)\n",
           bias->gz_bias, gyro_raw_to_dps(bias->gz_bias));

    return 0;
}

int main(void)
{
    mpu6500_sample_t s;
    gyro_bias_t gyro_bias;
    int rc;
    uint32_t sample_idx = 0u;

    printf("\nMPU6500 I2C calibrated sensor read test\n");
    printf("I2C base = 0x%08X\n", (unsigned)I2C_BASE);

    // Set a conservative divisor first. Adjust as needed once basic comms work.
    i2c_wr32(REG_DIVISOR, 250u);
    printf("REG_DIVISOR set to 250\n");

    rc = mpu6500_init();
    if (rc != 0) {
        while (1) {
            uint32_t status = i2c_rd32(REG_STATUS);
            printf("MPU6500 init FAILED rc=%d STATUS=0x%08lX\n", rc, (unsigned long)status);
            usleep(500000);
        }
    }

    rc = mpu6500_calibrate_gyro(&gyro_bias);
    if (rc != 0) {
        while (1) {
            uint32_t status = i2c_rd32(REG_STATUS);
            printf("Gyro calibration FAILED rc=%d STATUS=0x%08lX\n", rc, (unsigned long)status);
            usleep(500000);
        }
    }

    printf("\nStreaming calibrated values:\n");
    printf("idx |   ax[g]   ay[g]   az[g] | temp[C] |  gx[dps]  gy[dps]  gz[dps]\n");
    printf("----+-------------------------+---------+---------------------------\n");

    while (1) {
        float ax_g;
        float ay_g;
        float az_g;
        float temp_c;
        float gx_dps;
        float gy_dps;
        float gz_dps;

        rc = mpu6500_read_sample(&s);

        if (rc == 0) {
            ax_g = accel_raw_to_g(s.ax);
            ay_g = accel_raw_to_g(s.ay);
            az_g = accel_raw_to_g(s.az);
            temp_c = temp_raw_to_c(s.temp);

            gx_dps = gyro_raw_to_dps(((float)s.gx) - gyro_bias.gx_bias);
            gy_dps = gyro_raw_to_dps(((float)s.gy) - gyro_bias.gy_bias);
            gz_dps = gyro_raw_to_dps(((float)s.gz) - gyro_bias.gz_bias);

            printf("%3lu | %7.3f %7.3f %7.3f | %7.2f | %8.3f %8.3f %8.3f\n",
                   (unsigned long)sample_idx,
                   ax_g, ay_g, az_g,
                   temp_c,
                   gx_dps, gy_dps, gz_dps);
            sample_idx++;
        } else {
            uint32_t status = i2c_rd32(REG_STATUS);
            printf("Sample read FAILED rc=%d STATUS=0x%08lX\n", rc, (unsigned long)status);
        }

        usleep(STREAM_DELAY_US);
    }

    return 0;
}
