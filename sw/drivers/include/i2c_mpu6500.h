#ifndef I2C_MPU6500_H
#define I2C_MPU6500_H

#include <stdint.h>
#include <stdbool.h>

/*----------------------------------------------------------------------------
 * MPU-6500 I2C address
 *----------------------------------------------------------------------------*/
#define MPU6500_I2C_ADDR             0x68u

/*----------------------------------------------------------------------------
 * MPU-6500 register map
 *----------------------------------------------------------------------------*/
#define MPU6500_REG_SMPLRT_DIV       0x19u
#define MPU6500_REG_CONFIG           0x1Au
#define MPU6500_REG_GYRO_CONFIG      0x1Bu
#define MPU6500_REG_ACCEL_CONFIG     0x1Cu
#define MPU6500_REG_ACCEL_CONFIG2    0x1Du
#define MPU6500_REG_INT_PIN_CFG      0x37u
#define MPU6500_REG_INT_ENABLE       0x38u
#define MPU6500_REG_ACCEL_XOUT_H     0x3Bu
#define MPU6500_REG_TEMP_OUT_H       0x41u
#define MPU6500_REG_GYRO_XOUT_H      0x43u
#define MPU6500_REG_PWR_MGMT_1       0x6Bu
#define MPU6500_REG_PWR_MGMT_2       0x6Cu
#define MPU6500_REG_WHO_AM_I         0x75u

/*----------------------------------------------------------------------------
 * Expected WHO_AM_I value
 *----------------------------------------------------------------------------*/
#define MPU6500_WHO_AM_I_EXPECTED    0x70u

/*----------------------------------------------------------------------------
 * Full-scale assumptions used by the simple conversion helpers below
 *
 * These match the "basic config" helper in the .c file:
 * - accel  = +/-2g
 * - gyro   = +/-250 dps
 *----------------------------------------------------------------------------*/
#define MPU6500_ACCEL_LSB_PER_G      16384.0f
#define MPU6500_GYRO_LSB_PER_DPS     131.0f

/*----------------------------------------------------------------------------
 * Status / result codes
 *----------------------------------------------------------------------------*/
typedef enum
{
    MPU6500_OK = 0,
    MPU6500_ERR_NULL = -1,
    MPU6500_ERR_I2C = -2,
    MPU6500_ERR_WHO_AM_I = -3
} mpu6500_status_t;

/*----------------------------------------------------------------------------
 * Raw sensor sample
 *----------------------------------------------------------------------------*/
typedef struct
{
    int16_t ax;
    int16_t ay;
    int16_t az;

    int16_t temp_raw;

    int16_t gx;
    int16_t gy;
    int16_t gz;
} mpu6500_raw_sample_t;

/*----------------------------------------------------------------------------
 * Converted sensor sample
 *----------------------------------------------------------------------------*/
typedef struct
{
    float ax_g;
    float ay_g;
    float az_g;

    float temp_c;
    float temp_f;

    float gx_dps;
    float gy_dps;
    float gz_dps;
} mpu6500_scaled_sample_t;

/*----------------------------------------------------------------------------
 * Low-level register helpers
 *----------------------------------------------------------------------------*/

/* Write one MPU-6500 register. */
bool mpu6500_write_reg(uint32_t base, uint8_t reg_addr, uint8_t value);

/* Read one MPU-6500 register. */
bool mpu6500_read_reg(uint32_t base, uint8_t reg_addr, uint8_t *value);

/* Read multiple MPU-6500 registers starting at start_reg. */
bool mpu6500_read_regs(uint32_t base, uint8_t start_reg, uint8_t *buffer, uint8_t length);

/*----------------------------------------------------------------------------
 * Device-level helpers
 *----------------------------------------------------------------------------*/

/* Read WHO_AM_I register. */
bool mpu6500_read_who_am_i(uint32_t base, uint8_t *who_am_i);

/* Return true if WHO_AM_I matches expected MPU-6500 value. */
bool mpu6500_probe(uint32_t base);

/*
 * Basic initialization:
 * - wake device
 * - enable accel/gyro axes
 * - set sample-rate divider to 0
 * - set CONFIG = 0x01
 * - set gyro full scale = +/-250 dps
 * - set accel full scale = +/-2g
 * - set ACCEL_CONFIG2 = 0x01
 */
mpu6500_status_t mpu6500_init_basic(uint32_t base);

/*----------------------------------------------------------------------------
 * Sample read helpers
 *----------------------------------------------------------------------------*/

/* Read the full 14-byte accel/temp/gyro burst into a raw sample struct. */
bool mpu6500_read_raw_sample(uint32_t base, mpu6500_raw_sample_t *sample);

/* Convert one raw sample into engineering units. */
void mpu6500_convert_sample(const mpu6500_raw_sample_t *raw,
                            mpu6500_scaled_sample_t *scaled);

/* Read and convert one sample in one call. */
mpu6500_status_t mpu6500_read_scaled_sample(uint32_t base,
                                            mpu6500_scaled_sample_t *sample);

#endif /* I2C_MPU6500_H */