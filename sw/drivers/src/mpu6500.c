#include "mpu6500.h"

/*----------------------------------------------------------------------------
 * Internal helpers
 *----------------------------------------------------------------------------*/
static int16_t mpu6500_be16_to_i16(uint8_t msb, uint8_t lsb)
{
    return (int16_t)(((uint16_t)msb << 8) | (uint16_t)lsb);
}

static i2c_status_t mpu6500_read_bytes(const mpu6500_t *dev,
                                       uint8_t reg,
                                       uint8_t *data,
                                       uint32_t len)
{
    if ((dev == NULL) || ((data == NULL) && (len != 0u)))
    {
        return I2C_ERR_NULL_PTR;
    }

    return i2c_reg_read_bytes_timeout(dev->addr7,
                                      reg,
                                      data,
                                      (size_t)len,
                                      dev->timeout_poll_count);
}

static i2c_status_t mpu6500_write_reg_checked(const mpu6500_t *dev,
                                              uint8_t reg,
                                              uint8_t value)
{
    if (dev == NULL)
    {
        return I2C_ERR_NULL_PTR;
    }

    return i2c_reg_write8_timeout(dev->addr7,
                                  reg,
                                  value,
                                  dev->timeout_poll_count);
}

static i2c_status_t mpu6500_read_reg_checked(const mpu6500_t *dev,
                                             uint8_t reg,
                                             uint8_t *value)
{
    if ((dev == NULL) || (value == NULL))
    {
        return I2C_ERR_NULL_PTR;
    }

    return i2c_reg_read8_timeout(dev->addr7,
                                 reg,
                                 value,
                                 dev->timeout_poll_count);
}

/*----------------------------------------------------------------------------
 * Public API
 *----------------------------------------------------------------------------*/
void mpu6500_init_struct(mpu6500_t *dev,
                         uint8_t addr7,
                         uint32_t timeout_poll_count)
{
    if (dev == NULL)
    {
        return;
    }

    dev->addr7 = addr7;
    dev->timeout_poll_count = timeout_poll_count;
    dev->accel_fs = MPU6500_ACCEL_FS_2G;
    dev->gyro_fs  = MPU6500_GYRO_FS_250DPS;
}

i2c_status_t mpu6500_soft_reset(const mpu6500_t *dev)
{
    return mpu6500_write_reg_checked(dev,
                                     MPU6500_REG_PWR_MGMT_1,
                                     MPU6500_PWR_MGMT_1_DEVICE_RESET);
}

i2c_status_t mpu6500_signal_path_reset(const mpu6500_t *dev)
{
    return mpu6500_write_reg_checked(dev,
                                     MPU6500_REG_SIGNAL_PATH_RESET,
                                     MPU6500_SIGNAL_PATH_RESET_ALL);
}

i2c_status_t mpu6500_wake(mpu6500_t *dev)
{
    i2c_status_t status;

    if (dev == NULL)
    {
        return I2C_ERR_NULL_PTR;
    }

    status = mpu6500_write_reg_checked(dev,
                                       MPU6500_REG_PWR_MGMT_1,
                                       MPU6500_PWR_MGMT_1_CLKSEL_PLL_XGYRO);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_write_reg_checked(dev,
                                       MPU6500_REG_PWR_MGMT_2,
                                       0x00u);
    return status;
}

i2c_status_t mpu6500_sleep(const mpu6500_t *dev)
{
    return mpu6500_write_reg_checked(dev,
                                     MPU6500_REG_PWR_MGMT_1,
                                     MPU6500_PWR_MGMT_1_SLEEP);
}

i2c_status_t mpu6500_set_accel_fs(mpu6500_t *dev, mpu6500_accel_fs_t fs)
{
    i2c_status_t status;
    uint8_t value;

    if (dev == NULL)
    {
        return I2C_ERR_NULL_PTR;
    }

    value = (uint8_t)(((uint8_t)fs & 0x03u) << 3);

    status = mpu6500_write_reg_checked(dev,
                                       MPU6500_REG_ACCEL_CONFIG,
                                       value);
    if (status != I2C_OK)
    {
        return status;
    }

    dev->accel_fs = fs;
    return I2C_OK;
}

i2c_status_t mpu6500_set_gyro_fs(mpu6500_t *dev, mpu6500_gyro_fs_t fs)
{
    i2c_status_t status;
    uint8_t value;

    if (dev == NULL)
    {
        return I2C_ERR_NULL_PTR;
    }

    value = (uint8_t)(((uint8_t)fs & 0x03u) << 3);

    status = mpu6500_write_reg_checked(dev,
                                       MPU6500_REG_GYRO_CONFIG,
                                       value);
    if (status != I2C_OK)
    {
        return status;
    }

    dev->gyro_fs = fs;
    return I2C_OK;
}

i2c_status_t mpu6500_init_default(mpu6500_t *dev)
{
    i2c_status_t status;

    if (dev == NULL)
    {
        return I2C_ERR_NULL_PTR;
    }

    status = mpu6500_wake(dev);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_write_reg_checked(dev, MPU6500_REG_SMPLRT_DIV, 0x04u);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_write_reg_checked(dev, MPU6500_REG_CONFIG, 0x03u);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_set_gyro_fs(dev, MPU6500_GYRO_FS_250DPS);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_set_accel_fs(dev, MPU6500_ACCEL_FS_2G);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_write_reg_checked(dev, MPU6500_REG_ACCEL_CONFIG2, 0x03u);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_write_reg_checked(dev, MPU6500_REG_FIFO_EN, 0x00u);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_write_reg_checked(dev, MPU6500_REG_USER_CTRL, 0x00u);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_write_reg_checked(dev, MPU6500_REG_INT_PIN_CFG, 0x00u);
    if (status != I2C_OK)
    {
        return status;
    }

    status = mpu6500_write_reg_checked(dev, MPU6500_REG_INT_ENABLE, 0x00u);
    return status;
}

i2c_status_t mpu6500_read_reg(const mpu6500_t *dev, uint8_t reg, uint8_t *value)
{
    return mpu6500_read_reg_checked(dev, reg, value);
}

i2c_status_t mpu6500_write_reg(const mpu6500_t *dev, uint8_t reg, uint8_t value)
{
    return mpu6500_write_reg_checked(dev, reg, value);
}

i2c_status_t mpu6500_read_who_am_i(const mpu6500_t *dev, uint8_t *value)
{
    return mpu6500_read_reg_checked(dev, MPU6500_REG_WHO_AM_I, value);
}

bool mpu6500_who_am_i_valid(uint8_t value)
{
    return value == MPU6500_WHO_AM_I_EXPECTED;
}

i2c_status_t mpu6500_read_sample_raw(const mpu6500_t *dev,
                                     mpu6500_raw_sample_t *sample)
{
    i2c_status_t status;
    uint8_t buf[14];

    if ((dev == NULL) || (sample == NULL))
    {
        return I2C_ERR_NULL_PTR;
    }

    status = mpu6500_read_bytes(dev,
                                MPU6500_REG_ACCEL_XOUT_H,
                                buf,
                                14u);
    if (status != I2C_OK)
    {
        return status;
    }

    sample->accel.x = mpu6500_be16_to_i16(buf[0],  buf[1]);
    sample->accel.y = mpu6500_be16_to_i16(buf[2],  buf[3]);
    sample->accel.z = mpu6500_be16_to_i16(buf[4],  buf[5]);
    sample->temp    = mpu6500_be16_to_i16(buf[6],  buf[7]);
    sample->gyro.x  = mpu6500_be16_to_i16(buf[8],  buf[9]);
    sample->gyro.y  = mpu6500_be16_to_i16(buf[10], buf[11]);
    sample->gyro.z  = mpu6500_be16_to_i16(buf[12], buf[13]);

    return I2C_OK;
}

i2c_status_t mpu6500_read_accel_raw(const mpu6500_t *dev,
                                    mpu6500_vec3i16_t *accel)
{
    i2c_status_t status;
    uint8_t buf[6];

    if ((dev == NULL) || (accel == NULL))
    {
        return I2C_ERR_NULL_PTR;
    }

    status = mpu6500_read_bytes(dev,
                                MPU6500_REG_ACCEL_XOUT_H,
                                buf,
                                6u);
    if (status != I2C_OK)
    {
        return status;
    }

    accel->x = mpu6500_be16_to_i16(buf[0], buf[1]);
    accel->y = mpu6500_be16_to_i16(buf[2], buf[3]);
    accel->z = mpu6500_be16_to_i16(buf[4], buf[5]);

    return I2C_OK;
}

i2c_status_t mpu6500_read_gyro_raw(const mpu6500_t *dev,
                                   mpu6500_vec3i16_t *gyro)
{
    i2c_status_t status;
    uint8_t buf[6];

    if ((dev == NULL) || (gyro == NULL))
    {
        return I2C_ERR_NULL_PTR;
    }

    status = mpu6500_read_bytes(dev,
                                MPU6500_REG_GYRO_XOUT_H,
                                buf,
                                6u);
    if (status != I2C_OK)
    {
        return status;
    }

    gyro->x = mpu6500_be16_to_i16(buf[0], buf[1]);
    gyro->y = mpu6500_be16_to_i16(buf[2], buf[3]);
    gyro->z = mpu6500_be16_to_i16(buf[4], buf[5]);

    return I2C_OK;
}

i2c_status_t mpu6500_read_temp_raw(const mpu6500_t *dev,
                                   int16_t *temp_raw)
{
    i2c_status_t status;
    uint8_t buf[2];

    if ((dev == NULL) || (temp_raw == NULL))
    {
        return I2C_ERR_NULL_PTR;
    }

    status = mpu6500_read_bytes(dev,
                                MPU6500_REG_TEMP_OUT_H,
                                buf,
                                2u);
    if (status != I2C_OK)
    {
        return status;
    }

    *temp_raw = mpu6500_be16_to_i16(buf[0], buf[1]);
    return I2C_OK;
}

float mpu6500_accel_lsb_per_g(mpu6500_accel_fs_t fs)
{
    switch (fs)
    {
        case MPU6500_ACCEL_FS_2G:  return 16384.0f;
        case MPU6500_ACCEL_FS_4G:  return 8192.0f;
        case MPU6500_ACCEL_FS_8G:  return 4096.0f;
        case MPU6500_ACCEL_FS_16G: return 2048.0f;
        default:                   return 16384.0f;
    }
}

float mpu6500_gyro_lsb_per_dps(mpu6500_gyro_fs_t fs)
{
    switch (fs)
    {
        case MPU6500_GYRO_FS_250DPS:  return 131.0f;
        case MPU6500_GYRO_FS_500DPS:  return 65.5f;
        case MPU6500_GYRO_FS_1000DPS: return 32.8f;
        case MPU6500_GYRO_FS_2000DPS: return 16.4f;
        default:                      return 131.0f;
    }
}

float mpu6500_accel_raw_to_g(int16_t raw, mpu6500_accel_fs_t fs)
{
    return ((float)raw) / mpu6500_accel_lsb_per_g(fs);
}

float mpu6500_gyro_raw_to_dps(int16_t raw, mpu6500_gyro_fs_t fs)
{
    return ((float)raw) / mpu6500_gyro_lsb_per_dps(fs);
}

float mpu6500_temp_raw_to_c(int16_t raw)
{
    return (((float)raw) / 333.87f) + 21.0f;
}

float mpu6500_temp_raw_to_f(int16_t raw)
{
    float c = mpu6500_temp_raw_to_c(raw);
    return (c * 9.0f / 5.0f) + 32.0f;
}