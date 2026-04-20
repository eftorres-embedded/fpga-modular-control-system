#ifndef MPU6500_H
#define MPU6500_H

#include <stdint.h>
#include <stdbool.h>

#include "i2c_regs.h"

/*----------------------------------------------------------------------------
 * Device address
 *
 * MPU-6500 7-bit slave address is 0b110100X.
 * AD0 low  -> 0x68
 * AD0 high -> 0x69
 *----------------------------------------------------------------------------*/
#ifndef MPU6500_I2C_ADDR
#define MPU6500_I2C_ADDR        0x68u
#endif

/*----------------------------------------------------------------------------
 * Common register addresses
 *----------------------------------------------------------------------------*/
#define MPU6500_REG_SMPLRT_DIV      0x19u
#define MPU6500_REG_CONFIG          0x1Au
#define MPU6500_REG_GYRO_CONFIG     0x1Bu
#define MPU6500_REG_ACCEL_CONFIG    0x1Cu
#define MPU6500_REG_ACCEL_CONFIG2   0x1Du
#define MPU6500_REG_INT_ENABLE      0x38u
#define MPU6500_REG_ACCEL_XOUT_H    0x3Bu
#define MPU6500_REG_ACCEL_XOUT_L    0x3Cu
#define MPU6500_REG_ACCEL_YOUT_H    0x3Du
#define MPU6500_REG_ACCEL_YOUT_L    0x3Eu
#define MPU6500_REG_ACCEL_ZOUT_H    0x3Fu
#define MPU6500_REG_ACCEL_ZOUT_L    0x40u
#define MPU6500_REG_TEMP_OUT_H      0x41u
#define MPU6500_REG_TEMP_OUT_L      0x42u
#define MPU6500_REG_GYRO_XOUT_H     0x43u
#define MPU6500_REG_GYRO_XOUT_L     0x44u
#define MPU6500_REG_GYRO_YOUT_H     0x45u
#define MPU6500_REG_GYRO_YOUT_L     0x46u
#define MPU6500_REG_GYRO_ZOUT_H     0x47u
#define MPU6500_REG_GYRO_ZOUT_L     0x48u
#define MPU6500_REG_SIGNAL_PATH_RESET 0x68u
#define MPU6500_REG_USER_CTRL       0x6Au
#define MPU6500_REG_PWR_MGMT_1      0x6Bu
#define MPU6500_REG_PWR_MGMT_2      0x6Cu
#define MPU6500_REG_WHO_AM_I        0x75u

/*----------------------------------------------------------------------------
 * Useful bit values
 *----------------------------------------------------------------------------*/
#define MPU6500_WHO_AM_I_VALUE      0x70u

#define MPU6500_PWR1_DEVICE_RESET   0x80u
#define MPU6500_PWR1_SLEEP          0x40u
#define MPU6500_PWR1_CLKSEL_INTERNAL 0x00u
#define MPU6500_PWR1_CLKSEL_PLL_XGYRO 0x01u

#define MPU6500_ACCEL_FS_SEL_2G     0x00u
#define MPU6500_ACCEL_FS_SEL_4G     0x08u
#define MPU6500_ACCEL_FS_SEL_8G     0x10u
#define MPU6500_ACCEL_FS_SEL_16G    0x18u

#define MPU6500_GYRO_FS_SEL_250DPS  0x00u
#define MPU6500_GYRO_FS_SEL_500DPS  0x08u
#define MPU6500_GYRO_FS_SEL_1000DPS 0x10u
#define MPU6500_GYRO_FS_SEL_2000DPS 0x18u

#define MPU6500_INT_ENABLE_RAW_RDY  0x01u
#define MPU6500_INT_ENABLE_MOT      0x40u

/*----------------------------------------------------------------------------
 * Driver status
 *----------------------------------------------------------------------------*/
typedef enum
{
    MPU6500_OK = 0,
    MPU6500_ERR_NULL_PTR = -1,
    MPU6500_ERR_I2C = -2,
    MPU6500_ERR_WHOAMI = -3
} mpu6500_status_t;

/*----------------------------------------------------------------------------
 * Raw sample containers
 *----------------------------------------------------------------------------*/
typedef struct
{
    int16_t x;
    int16_t y;
    int16_t z;
} mpu6500_vec3_raw_t;

typedef struct
{
    mpu6500_vec3_raw_t accel;
    int16_t            temp;
    mpu6500_vec3_raw_t gyro;
} mpu6500_raw_sample_t;

/*----------------------------------------------------------------------------
 * Register access
 *----------------------------------------------------------------------------*/
mpu6500_status_t mpu6500_write_reg(uint8_t reg, uint8_t value);
mpu6500_status_t mpu6500_read_reg(uint8_t reg, uint8_t *value);
mpu6500_status_t mpu6500_read_regs(uint8_t start_reg, uint8_t *buf, uint32_t len);

/*----------------------------------------------------------------------------
 * Device helpers
 *----------------------------------------------------------------------------*/
mpu6500_status_t mpu6500_read_whoami(uint8_t *value);
mpu6500_status_t mpu6500_set_sleep(bool enable);
mpu6500_status_t mpu6500_init_default(void);
mpu6500_status_t mpu6500_read_accel_raw(mpu6500_vec3_raw_t *accel);
mpu6500_status_t mpu6500_read_gyro_raw(mpu6500_vec3_raw_t *gyro);
mpu6500_status_t mpu6500_read_all_raw(mpu6500_raw_sample_t *sample);

#endif /* MPU6500_H */
