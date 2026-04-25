#include "i2c_mpu6500.h"

#include <stddef.h>
#include <unistd.h>

#include "i2c_regs.h"

/*----------------------------------------------------------------------------
 * Local helpers
 *----------------------------------------------------------------------------*/
static int16_t mpu6500_be_to_s16(uint8_t msb, uint8_t lsb)
{
    return (int16_t)(((uint16_t)msb << 8) | (uint16_t)lsb);
}

static float mpu6500_temp_raw_to_c(int16_t temp_raw)
{
    /*
     * MPU-6500 temperature conversion:
     * Temp(degC) = (TEMP_OUT_Register / 333.87) + 21.0
     */
    return ((float)temp_raw / 333.87f) + 21.0f;
}

/*----------------------------------------------------------------------------
 * Low-level register helpers
 *----------------------------------------------------------------------------*/

/* Write one MPU-6500 register. */
bool mpu6500_write_reg(uint32_t base, uint8_t reg_addr, uint8_t value)
{
    uint8_t tx[2];
    uint8_t flags;

    tx[0] = reg_addr;
    tx[1] = value;

    flags = i2c_tx_buf(base, MPU6500_I2C_ADDR, tx, 2u);

    return (flags == I2C_TX_OK);
}

/* Read one MPU-6500 register. */
bool mpu6500_read_reg(uint32_t base, uint8_t reg_addr, uint8_t *value)
{
    if (value == NULL)
    {
        return false;
    }

    return i2c_txrx_buf(base, MPU6500_I2C_ADDR, &reg_addr, 1u, value, 1u);
}

/* Read multiple MPU-6500 registers starting at start_reg. */
bool mpu6500_read_regs(uint32_t base, uint8_t start_reg, uint8_t *buffer, uint8_t length)
{
    if ((buffer == NULL) && (length != 0u))
    {
        return false;
    }

    return i2c_txrx_buf(base, MPU6500_I2C_ADDR, &start_reg, 1u, buffer, length);
}

/*----------------------------------------------------------------------------
 * Device-level helpers
 *----------------------------------------------------------------------------*/

/* Read WHO_AM_I register. */
bool mpu6500_read_who_am_i(uint32_t base, uint8_t *who_am_i)
{
    return mpu6500_read_reg(base, MPU6500_REG_WHO_AM_I, who_am_i);
}

/* Return true if WHO_AM_I matches expected MPU-6500 value. */
bool mpu6500_probe(uint32_t base)
{
    uint8_t who_am_i = 0u;

    if (!mpu6500_read_who_am_i(base, &who_am_i))
    {
        return false;
    }

    return (who_am_i == MPU6500_WHO_AM_I_EXPECTED);
}

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
mpu6500_status_t mpu6500_init_basic(uint32_t base)
{
    uint8_t who_am_i = 0u;

    if (!mpu6500_read_who_am_i(base, &who_am_i))
    {
        return MPU6500_ERR_I2C;
    }

    if (who_am_i != MPU6500_WHO_AM_I_EXPECTED)
    {
        return MPU6500_ERR_WHO_AM_I;
    }

    if (!mpu6500_write_reg(base, MPU6500_REG_PWR_MGMT_1, 0x01u))
    {
        return MPU6500_ERR_I2C;
    }

    usleep(50000);

    if (!mpu6500_write_reg(base, MPU6500_REG_PWR_MGMT_2, 0x00u))
    {
        return MPU6500_ERR_I2C;
    }

    if (!mpu6500_write_reg(base, MPU6500_REG_SMPLRT_DIV, 0x00u))
    {
        return MPU6500_ERR_I2C;
    }

    if (!mpu6500_write_reg(base, MPU6500_REG_CONFIG, 0x01u))
    {
        return MPU6500_ERR_I2C;
    }

    if (!mpu6500_write_reg(base, MPU6500_REG_GYRO_CONFIG, 0x00u))
    {
        return MPU6500_ERR_I2C;
    }

    if (!mpu6500_write_reg(base, MPU6500_REG_ACCEL_CONFIG, 0x00u))
    {
        return MPU6500_ERR_I2C;
    }

    if (!mpu6500_write_reg(base, MPU6500_REG_ACCEL_CONFIG2, 0x01u))
    {
        return MPU6500_ERR_I2C;
    }

    usleep(10000);

    return MPU6500_OK;
}

/*----------------------------------------------------------------------------
 * Sample read helpers
 *----------------------------------------------------------------------------*/

/* Read the full 14-byte accel/temp/gyro burst into a raw sample struct. */
bool mpu6500_read_raw_sample(uint32_t base, mpu6500_raw_sample_t *sample)
{
    uint8_t burst[14];

    if (sample == NULL)
    {
        return false;
    }

    if (!mpu6500_read_regs(base, MPU6500_REG_ACCEL_XOUT_H, burst, 14u))
    {
        return false;
    }

    sample->ax       = mpu6500_be_to_s16(burst[0],  burst[1]);
    sample->ay       = mpu6500_be_to_s16(burst[2],  burst[3]);
    sample->az       = mpu6500_be_to_s16(burst[4],  burst[5]);
    sample->temp_raw = mpu6500_be_to_s16(burst[6],  burst[7]);
    sample->gx       = mpu6500_be_to_s16(burst[8],  burst[9]);
    sample->gy       = mpu6500_be_to_s16(burst[10], burst[11]);
    sample->gz       = mpu6500_be_to_s16(burst[12], burst[13]);

    return true;
}

/* Convert one raw sample into engineering units. */
void mpu6500_convert_sample(const mpu6500_raw_sample_t *raw,
                            mpu6500_scaled_sample_t *scaled)
{
    if ((raw == NULL) || (scaled == NULL))
    {
        return;
    }

    scaled->ax_g = (float)raw->ax / MPU6500_ACCEL_LSB_PER_G;
    scaled->ay_g = (float)raw->ay / MPU6500_ACCEL_LSB_PER_G;
    scaled->az_g = (float)raw->az / MPU6500_ACCEL_LSB_PER_G;

    scaled->temp_c = mpu6500_temp_raw_to_c(raw->temp_raw);
    scaled->temp_f = (scaled->temp_c * 9.0f / 5.0f) + 32.0f;

    scaled->gx_dps = (float)raw->gx / MPU6500_GYRO_LSB_PER_DPS;
    scaled->gy_dps = (float)raw->gy / MPU6500_GYRO_LSB_PER_DPS;
    scaled->gz_dps = (float)raw->gz / MPU6500_GYRO_LSB_PER_DPS;
}

/* Read and convert one sample in one call. */
mpu6500_status_t mpu6500_read_scaled_sample(uint32_t base,
                                            mpu6500_scaled_sample_t *sample)
{
    mpu6500_raw_sample_t raw;

    if (sample == NULL)
    {
        return MPU6500_ERR_NULL;
    }

    if (!mpu6500_read_raw_sample(base, &raw))
    {
        return MPU6500_ERR_I2C;
    }

    mpu6500_convert_sample(&raw, sample);
    return MPU6500_OK;
}