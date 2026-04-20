#include "adxl345.h"
#include "spi_regs.h"

/*----------------------------------------------------------------------------
 * Internal helpers
 *----------------------------------------------------------------------------*/

/*
 * Build the first SPI command byte for an ADXL345 register access.
 *
 * Layout:
 *   bit7 = read/write
 *   bit6 = multiple-byte
 *   bit5:0 = register address
 */
static inline uint8_t adxl345_spi_cmd(uint8_t reg, bool is_read, bool multi_byte)
{
    uint8_t cmd = (uint8_t)(reg & ADXL345_SPI_ADDR_MASK);

    if (is_read) {
        cmd |= ADXL345_SPI_READ_BIT;
    }

    if (multi_byte) {
        cmd |= ADXL345_SPI_MB_BIT;
    }

    return cmd;
}


/*----------------------------------------------------------------------------
 * Basic register write
 *----------------------------------------------------------------------------*/

/*
 * Write one ADXL345 register.
 *
 * SPI sequence:
 *   byte 0: command byte (write, single-byte)
 *   byte 1: register data
 *
 * The first returned byte is ignored because during the command phase the
 * slave is not returning meaningful register data for us.
 */
adxl345_status_t adxl345_write_reg(uint8_t reg, uint8_t value)
{
    (void)spi_transfer_byte_blocking(adxl345_spi_cmd(reg, false, false), false);
    (void)spi_transfer_byte_blocking(value, true);
    return ADXL345_OK;
}


/*----------------------------------------------------------------------------
 * Basic register read
 *----------------------------------------------------------------------------*/

/*
 * Read one ADXL345 register.
 *
 * SPI sequence:
 *   byte 0: command byte (read, single-byte)
 *   byte 1: dummy byte to clock in the response
 */
adxl345_status_t adxl345_read_reg(uint8_t reg, uint8_t *value)
{
    if (value == 0) {
        return ADXL345_ERR_NULL_PTR;
    }

    (void)spi_transfer_byte_blocking(adxl345_spi_cmd(reg, true, false), false);
    *value = spi_transfer_byte_blocking(0x00u, true);

    return ADXL345_OK;
}


/*----------------------------------------------------------------------------
 * Multi-register read
 *----------------------------------------------------------------------------*/

/*
 * Read a consecutive register window starting at start_reg.
 *
 * This uses the ADXL345 multiple-byte SPI mode so CS stays active across the
 * whole burst.
 */
adxl345_status_t adxl345_read_regs(uint8_t start_reg, uint8_t *buf, uint32_t len)
{
    uint32_t i;

    if ((buf == 0) || (len == 0u)) {
        return ADXL345_ERR_NULL_PTR;
    }

    /* Send burst-read command, keep transaction open. */
    (void)spi_transfer_byte_blocking(adxl345_spi_cmd(start_reg, true, (len > 1u)), false);

    /* Clock in all data bytes. Mark only the last byte as final. */
    for (i = 0u; i < len; ++i) {
        bool final_byte = (i == (len - 1u));
        buf[i] = spi_transfer_byte_blocking(0x00u, final_byte);
    }

    return ADXL345_OK;
}


/*----------------------------------------------------------------------------
 * Device helpers
 *----------------------------------------------------------------------------*/

adxl345_status_t adxl345_read_device_id(uint8_t *devid)
{
    return adxl345_read_reg(ADXL345_REG_DEVID, devid);
}

adxl345_status_t adxl345_set_bw_rate(uint8_t bw_rate)
{
    return adxl345_write_reg(ADXL345_REG_BW_RATE, bw_rate);
}

adxl345_status_t adxl345_set_data_format(uint8_t data_format)
{
    return adxl345_write_reg(ADXL345_REG_DATA_FORMAT, data_format);
}

adxl345_status_t adxl345_set_measure(bool enable)
{
    uint8_t power_ctl = enable ? ADXL345_POWER_CTL_MEASURE : 0x00u;
    return adxl345_write_reg(ADXL345_REG_POWER_CTL, power_ctl);
}


/*----------------------------------------------------------------------------
 * Read raw X/Y/Z axis sample
 *----------------------------------------------------------------------------*/

/*
 * Read all six data bytes in one burst:
 *   DATAX0, DATAX1, DATAY0, DATAY1, DATAZ0, DATAZ1
 *
 * The ADXL345 stores each axis in little-endian order:
 *   low byte first, then high byte
 */
adxl345_status_t adxl345_read_xyz_raw(adxl345_raw_xyz_t *xyz)
{
    uint8_t buf[6];

    if (xyz == 0) {
        return ADXL345_ERR_NULL_PTR;
    }

    adxl345_read_regs(ADXL345_REG_DATAX0, buf, 6u);

    xyz->x = (int16_t)((uint16_t)buf[0] | ((uint16_t)buf[1] << 8));
    xyz->y = (int16_t)((uint16_t)buf[2] | ((uint16_t)buf[3] << 8));
    xyz->z = (int16_t)((uint16_t)buf[4] | ((uint16_t)buf[5] << 8));

    return ADXL345_OK;
}


/*----------------------------------------------------------------------------
 * Conservative known-good bring-up sequence
 *----------------------------------------------------------------------------*/

/*
 * This routine intentionally keeps the configuration simple and explicit.
 *
 * Why DATA_FORMAT = 0x00 first?
 * - forces 4-wire SPI (SPI bit = 0)
 * - disables self-test
 * - leaves interrupts active-high
 * - right-justified output
 * - fixed 10-bit, +/-2g mode
 *
 * This is a good baseline for first communication bring-up.
 *
 * Note:
 * If you later want full-resolution mode, you can set:
 *   ADXL345_DATA_FORMAT_FULL_RES | ADXL345_RANGE_2G
 * after communication is verified.
 */
adxl345_status_t adxl345_init_default(void)
{
    uint8_t value;

    /* 1) Force a known-good 4-wire baseline. */
    adxl345_write_reg(ADXL345_REG_DATA_FORMAT, 0x00u);

    /* 2) Verify DATA_FORMAT readback. */
    adxl345_read_reg(ADXL345_REG_DATA_FORMAT, &value);
    if (value != 0x00u) {
        return ADXL345_ERR_DATA_FORMAT;
    }

    /* 3) Verify device identity. */
    adxl345_read_reg(ADXL345_REG_DEVID, &value);
    if (value != ADXL345_DEVID_VALUE) {
        return ADXL345_ERR_DEVID;
    }

    /* 4) Set a conservative output data rate: 100 Hz. */
    adxl345_write_reg(ADXL345_REG_BW_RATE, ADXL345_RATE_100_HZ);

    /* 5) Enter measurement mode. */
    adxl345_write_reg(ADXL345_REG_POWER_CTL, ADXL345_POWER_CTL_MEASURE);

    return ADXL345_OK;
}