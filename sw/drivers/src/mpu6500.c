#include "mpu6500.h"

/*----------------------------------------------------------------------------
 * Convert low/high byte pair to signed 16-bit.
 *----------------------------------------------------------------------------*/
static inline int16_t mpu6500_be16_to_i16(uint8_t hi, uint8_t lo)
{
    return (int16_t)(((uint16_t)hi << 8) | (uint16_t)lo);
}

/*----------------------------------------------------------------------------
 * Low-level register write
 *----------------------------------------------------------------------------*/
mpu6500_status_t mpu6500_write_reg(uint8_t reg, uint8_t value)
{
    if (i2c_start_blocking() != I2C_OK) {
        return MPU6500_ERR_I2C;
    }

    if (i2c_write_addr7_blocking(MPU6500_I2C_ADDR, false) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_write_byte_blocking(reg) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_write_byte_blocking(value) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_stop_blocking() != I2C_OK) {
        return MPU6500_ERR_I2C;
    }

    return MPU6500_OK;
}

/*----------------------------------------------------------------------------
 * Low-level single-register read
 *----------------------------------------------------------------------------*/
mpu6500_status_t mpu6500_read_reg(uint8_t reg, uint8_t *value)
{
    if (value == 0) {
        return MPU6500_ERR_NULL_PTR;
    }

    if (i2c_start_blocking() != I2C_OK) {
        return MPU6500_ERR_I2C;
    }

    if (i2c_write_addr7_blocking(MPU6500_I2C_ADDR, false) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_write_byte_blocking(reg) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_restart_blocking() != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_write_addr7_blocking(MPU6500_I2C_ADDR, true) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_read_byte_blocking(true, value) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_stop_blocking() != I2C_OK) {
        return MPU6500_ERR_I2C;
    }

    return MPU6500_OK;
}

/*----------------------------------------------------------------------------
 * Low-level burst read
 *----------------------------------------------------------------------------*/
mpu6500_status_t mpu6500_read_regs(uint8_t start_reg, uint8_t *buf, uint32_t len)
{
    uint32_t i;

    if ((buf == 0) || (len == 0u)) {
        return MPU6500_ERR_NULL_PTR;
    }

    if (i2c_start_blocking() != I2C_OK) {
        return MPU6500_ERR_I2C;
    }

    if (i2c_write_addr7_blocking(MPU6500_I2C_ADDR, false) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_write_byte_blocking(start_reg) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_restart_blocking() != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    if (i2c_write_addr7_blocking(MPU6500_I2C_ADDR, true) != I2C_OK) {
        (void)i2c_stop_blocking();
        return MPU6500_ERR_I2C;
    }

    for (i = 0u; i < len; ++i) {
        bool rd_last = (i == (len - 1u));

        if (i2c_read_byte_blocking(rd_last, &buf[i]) != I2C_OK) {
            (void)i2c_stop_blocking();
            return MPU6500_ERR_I2C;
        }
    }

    if (i2c_stop_blocking() != I2C_OK) {
        return MPU6500_ERR_I2C;
    }

    return MPU6500_OK;
}

/*----------------------------------------------------------------------------
 * Simple device helpers
 *----------------------------------------------------------------------------*/
mpu6500_status_t mpu6500_read_whoami(uint8_t *value)
{
    return mpu6500_read_reg(MPU6500_REG_WHO_AM_I, value);
}

mpu6500_status_t mpu6500_set_sleep(bool enable)
{
    uint8_t value;
    mpu6500_status_t st;

    st = mpu6500_read_reg(MPU6500_REG_PWR_MGMT_1, &value);
    if (st != MPU6500_OK) {
        return st;
    }

    if (enable) {
        value |= MPU6500_PWR1_SLEEP;
    } else {
        value &= (uint8_t)~MPU6500_PWR1_SLEEP;
    }

    return mpu6500_write_reg(MPU6500_REG_PWR_MGMT_1, value);
}

/*----------------------------------------------------------------------------
 * Conservative default init
 *
 * This brings the part out of sleep and selects simple baseline settings:
 * - clock source = PLL with X gyro
 * - sample rate divider = 0
 * - CONFIG = 0x01
 * - GYRO_CONFIG = +/-250 dps
 * - ACCEL_CONFIG = +/-2g
 * - ACCEL_CONFIG2 = 0x01 (184 Hz accel bandwidth)
 * - INT_ENABLE = 0x00
 *----------------------------------------------------------------------------*/
mpu6500_status_t mpu6500_init_default(void)
{
    uint8_t whoami = 0u;
    mpu6500_status_t st;

    st = mpu6500_write_reg(MPU6500_REG_PWR_MGMT_1, MPU6500_PWR1_CLKSEL_PLL_XGYRO);
    if (st != MPU6500_OK) {
        return st;
    }

    st = mpu6500_write_reg(MPU6500_REG_SMPLRT_DIV, 0x00u);
    if (st != MPU6500_OK) {
        return st;
    }

    st = mpu6500_write_reg(MPU6500_REG_CONFIG, 0x01u);
    if (st != MPU6500_OK) {
        return st;
    }

    st = mpu6500_write_reg(MPU6500_REG_GYRO_CONFIG, MPU6500_GYRO_FS_SEL_250DPS);
    if (st != MPU6500_OK) {
        return st;
    }

    st = mpu6500_write_reg(MPU6500_REG_ACCEL_CONFIG, MPU6500_ACCEL_FS_SEL_2G);
    if (st != MPU6500_OK) {
        return st;
    }

    st = mpu6500_write_reg(MPU6500_REG_ACCEL_CONFIG2, 0x01u);
    if (st != MPU6500_OK) {
        return st;
    }

    st = mpu6500_write_reg(MPU6500_REG_INT_ENABLE, 0x00u);
    if (st != MPU6500_OK) {
        return st;
    }

    st = mpu6500_read_whoami(&whoami);
    if (st != MPU6500_OK) {
        return st;
    }

    if (whoami != MPU6500_WHO_AM_I_VALUE) {
        return MPU6500_ERR_WHOAMI;
    }

    return MPU6500_OK;
}

/*----------------------------------------------------------------------------
 * Raw data reads
 *----------------------------------------------------------------------------*/
mpu6500_status_t mpu6500_read_accel_raw(mpu6500_vec3_raw_t *accel)
{
    uint8_t buf[6];
    mpu6500_status_t st;

    if (accel == 0) {
        return MPU6500_ERR_NULL_PTR;
    }

    st = mpu6500_read_regs(MPU6500_REG_ACCEL_XOUT_H, buf, 6u);
    if (st != MPU6500_OK) {
        return st;
    }

    accel->x = mpu6500_be16_to_i16(buf[0], buf[1]);
    accel->y = mpu6500_be16_to_i16(buf[2], buf[3]);
    accel->z = mpu6500_be16_to_i16(buf[4], buf[5]);

    return MPU6500_OK;
}

mpu6500_status_t mpu6500_read_gyro_raw(mpu6500_vec3_raw_t *gyro)
{
    uint8_t buf[6];
    mpu6500_status_t st;

    if (gyro == 0) {
        return MPU6500_ERR_NULL_PTR;
    }

    st = mpu6500_read_regs(MPU6500_REG_GYRO_XOUT_H, buf, 6u);
    if (st != MPU6500_OK) {
        return st;
    }

    gyro->x = mpu6500_be16_to_i16(buf[0], buf[1]);
    gyro->y = mpu6500_be16_to_i16(buf[2], buf[3]);
    gyro->z = mpu6500_be16_to_i16(buf[4], buf[5]);

    return MPU6500_OK;
}

mpu6500_status_t mpu6500_read_all_raw(mpu6500_raw_sample_t *sample)
{
    uint8_t buf[14];
    mpu6500_status_t st;

    if (sample == 0) {
        return MPU6500_ERR_NULL_PTR;
    }

    st = mpu6500_read_regs(MPU6500_REG_ACCEL_XOUT_H, buf, 14u);
    if (st != MPU6500_OK) {
        return st;
    }

    sample->accel.x = mpu6500_be16_to_i16(buf[0],  buf[1]);
    sample->accel.y = mpu6500_be16_to_i16(buf[2],  buf[3]);
    sample->accel.z = mpu6500_be16_to_i16(buf[4],  buf[5]);
    sample->temp    = mpu6500_be16_to_i16(buf[6],  buf[7]);
    sample->gyro.x  = mpu6500_be16_to_i16(buf[8],  buf[9]);
    sample->gyro.y  = mpu6500_be16_to_i16(buf[10], buf[11]);
    sample->gyro.z  = mpu6500_be16_to_i16(buf[12], buf[13]);

    return MPU6500_OK;
}
