#ifndef MPU6500_H
#define MPU6500_H

#include <stdint.h>
#include <stdbool.h>

#include "i2c_xfer.h"

/*----------------------------------------------------------------------------
 * I2C addressing
 *----------------------------------------------------------------------------*/
#define MPU6500_I2C_ADDR_AD0_LOW        0x68u
#define MPU6500_I2C_ADDR_AD0_HIGH       0x69u

/*----------------------------------------------------------------------------
 * Common register addresses
 *
 * These follow the standard MPU-6500 register map.
 *----------------------------------------------------------------------------*/
#define MPU6500_REG_SMPLRT_DIV          0x19u
#define MPU6500_REG_CONFIG              0x1Au
#define MPU6500_REG_GYRO_CONFIG         0x1Bu
#define MPU6500_REG_ACCEL_CONFIG        0x1Cu
#define MPU6500_REG_ACCEL_CONFIG2       0x1Du
#define MPU6500_REG_FIFO_EN             0x23u
#define MPU6500_REG_INT_PIN_CFG         0x37u
#define MPU6500_REG_INT_ENABLE          0x38u
#define MPU6500_REG_INT_STATUS          0x3Au
#define MPU6500_REG_ACCEL_XOUT_H        0x3Bu
#define MPU6500_REG_TEMP_OUT_H          0x41u
#define MPU6500_REG_GYRO_XOUT_H         0x43u
#define MPU6500_REG_SIGNAL_PATH_RESET   0x68u
#define MPU6500_REG_USER_CTRL           0x6Au
#define MPU6500_REG_PWR_MGMT_1          0x6Bu
#define MPU6500_REG_PWR_MGMT_2          0x6Cu
#define MPU6500_REG_WHO_AM_I            0x75u

/*----------------------------------------------------------------------------
 * Common bit values
 *----------------------------------------------------------------------------*/
#define MPU6500_PWR_MGMT_1_DEVICE_RESET     0x80u
#define MPU6500_PWR_MGMT_1_SLEEP            0x40u
#define MPU6500_PWR_MGMT_1_CLKSEL_INTERNAL  0x00u
#define MPU6500_PWR_MGMT_1_CLKSEL_PLL_XGYRO 0x01u

#define MPU6500_SIGNAL_PATH_RESET_ALL       0x07u

#define MPU6500_WHO_AM_I_EXPECTED           0x70u

/*----------------------------------------------------------------------------
 * Full-scale configuration enums
 *----------------------------------------------------------------------------*/
typedef enum
{
    MPU6500_ACCEL_FS_2G  = 0u,
    MPU6500_ACCEL_FS_4G  = 1u,
    MPU6500_ACCEL_FS_8G  = 2u,
    MPU6500_ACCEL_FS_16G = 3u
} mpu6500_accel_fs_t;

typedef enum
{
    MPU6500_GYRO_FS_250DPS  = 0u,
    MPU6500_GYRO_FS_500DPS  = 1u,
    MPU6500_GYRO_FS_1000DPS = 2u,
    MPU6500_GYRO_FS_2000DPS = 3u
} mpu6500_gyro_fs_t;

/*----------------------------------------------------------------------------
 * Driver object
 *----------------------------------------------------------------------------*/
typedef struct
{
    uint8_t addr7;
    uint32_t timeout_poll_count;

    mpu6500_accel_fs_t accel_fs;
    mpu6500_gyro_fs_t  gyro_fs;
} mpu6500_t;

/*----------------------------------------------------------------------------
 * Raw sample containers
 *----------------------------------------------------------------------------*/
typedef struct
{
    int16_t x;
    int16_t y;
    int16_t z;
} mpu6500_vec3i16_t;

typedef struct
{
    mpu6500_vec3i16_t accel;
    int16_t temp;
    mpu6500_vec3i16_t gyro;
} mpu6500_raw_sample_t;

/*----------------------------------------------------------------------------
 * Initialization / configuration
 *----------------------------------------------------------------------------*/
void mpu6500_init_struct(mpu6500_t *dev,
                         uint8_t addr7,
                         uint32_t timeout_poll_count);

i2c_status_t mpu6500_soft_reset(const mpu6500_t *dev);
i2c_status_t mpu6500_signal_path_reset(const mpu6500_t *dev);
i2c_status_t mpu6500_wake(mpu6500_t *dev);
i2c_status_t mpu6500_sleep(const mpu6500_t *dev);

i2c_status_t mpu6500_set_accel_fs(mpu6500_t *dev, mpu6500_accel_fs_t fs);
i2c_status_t mpu6500_set_gyro_fs(mpu6500_t *dev, mpu6500_gyro_fs_t fs);

i2c_status_t mpu6500_init_default(mpu6500_t *dev);

/*----------------------------------------------------------------------------
 * Register access helpers
 *----------------------------------------------------------------------------*/
i2c_status_t mpu6500_read_reg(const mpu6500_t *dev, uint8_t reg, uint8_t *value);
i2c_status_t mpu6500_write_reg(const mpu6500_t *dev, uint8_t reg, uint8_t value);

i2c_status_t mpu6500_read_who_am_i(const mpu6500_t *dev, uint8_t *value);
bool mpu6500_who_am_i_valid(uint8_t value);

/*----------------------------------------------------------------------------
 * Sensor reads
 *----------------------------------------------------------------------------*/
i2c_status_t mpu6500_read_sample_raw(const mpu6500_t *dev,
                                     mpu6500_raw_sample_t *sample);

i2c_status_t mpu6500_read_accel_raw(const mpu6500_t *dev,
                                    mpu6500_vec3i16_t *accel);

i2c_status_t mpu6500_read_gyro_raw(const mpu6500_t *dev,
                                   mpu6500_vec3i16_t *gyro);

i2c_status_t mpu6500_read_temp_raw(const mpu6500_t *dev,
                                   int16_t *temp_raw);

/*----------------------------------------------------------------------------
 * Conversion helpers
 *----------------------------------------------------------------------------*/
float mpu6500_accel_lsb_per_g(mpu6500_accel_fs_t fs);
float mpu6500_gyro_lsb_per_dps(mpu6500_gyro_fs_t fs);

float mpu6500_accel_raw_to_g(int16_t raw, mpu6500_accel_fs_t fs);
float mpu6500_gyro_raw_to_dps(int16_t raw, mpu6500_gyro_fs_t fs);

float mpu6500_temp_raw_to_c(int16_t raw);
float mpu6500_temp_raw_to_f(int16_t raw);

#endif /* MPU6500_H */