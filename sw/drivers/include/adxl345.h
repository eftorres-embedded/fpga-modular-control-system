#ifndef ADXL345_H
#define ADXL345_H

#include <stdint.h>
#include <stdbool.h>

/*----------------------------------------------------------------------------
 * ADXL345 register map
 *----------------------------------------------------------------------------*/
#define ADXL345_REG_DEVID          0x00u

#define ADXL345_REG_THRESH_TAP     0x1Du
#define ADXL345_REG_OFSX           0x1Eu
#define ADXL345_REG_OFSY           0x1Fu
#define ADXL345_REG_OFSZ           0x20u
#define ADXL345_REG_DUR            0x21u
#define ADXL345_REG_LATENT         0x22u
#define ADXL345_REG_WINDOW         0x23u
#define ADXL345_REG_THRESH_ACT     0x24u
#define ADXL345_REG_THRESH_INACT   0x25u
#define ADXL345_REG_TIME_INACT     0x26u
#define ADXL345_REG_ACT_INACT_CTL  0x27u
#define ADXL345_REG_THRESH_FF      0x28u
#define ADXL345_REG_TIME_FF        0x29u
#define ADXL345_REG_TAP_AXES       0x2Au
#define ADXL345_REG_ACT_TAP_STATUS 0x2Bu
#define ADXL345_REG_BW_RATE        0x2Cu
#define ADXL345_REG_POWER_CTL      0x2Du
#define ADXL345_REG_INT_ENABLE     0x2Eu
#define ADXL345_REG_INT_MAP        0x2Fu
#define ADXL345_REG_INT_SOURCE     0x30u
#define ADXL345_REG_DATA_FORMAT    0x31u

#define ADXL345_REG_DATAX0         0x32u
#define ADXL345_REG_DATAX1         0x33u
#define ADXL345_REG_DATAY0         0x34u
#define ADXL345_REG_DATAY1         0x35u
#define ADXL345_REG_DATAZ0         0x36u
#define ADXL345_REG_DATAZ1         0x37u

#define ADXL345_REG_FIFO_CTL       0x38u
#define ADXL345_REG_FIFO_STATUS    0x39u

/*----------------------------------------------------------------------------
 * Fixed device constants
 *----------------------------------------------------------------------------*/
#define ADXL345_DEVID_VALUE        0xE5u

/*----------------------------------------------------------------------------
 * SPI command byte fields
 *
 * ADXL345 SPI first byte:
 *   bit7 = R/W    (1=read, 0=write)
 *   bit6 = MB     (1=multiple-byte, 0=single-byte)
 *   bit5:0 = register address
 *----------------------------------------------------------------------------*/
#define ADXL345_SPI_READ_BIT       0x80u
#define ADXL345_SPI_MB_BIT         0x40u
#define ADXL345_SPI_ADDR_MASK      0x3Fu

/*----------------------------------------------------------------------------
 * BW_RATE register bits / common rate codes
 *----------------------------------------------------------------------------*/
#define ADXL345_BW_RATE_LOW_POWER  (1u << 4)

#define ADXL345_RATE_0P10_HZ       0x00u
#define ADXL345_RATE_0P20_HZ       0x01u
#define ADXL345_RATE_0P39_HZ       0x02u
#define ADXL345_RATE_0P78_HZ       0x03u
#define ADXL345_RATE_1P56_HZ       0x04u
#define ADXL345_RATE_3P13_HZ       0x05u
#define ADXL345_RATE_6P25_HZ       0x06u
#define ADXL345_RATE_12P5_HZ       0x07u
#define ADXL345_RATE_25_HZ         0x08u
#define ADXL345_RATE_50_HZ         0x09u
#define ADXL345_RATE_100_HZ        0x0Au
#define ADXL345_RATE_200_HZ        0x0Bu
#define ADXL345_RATE_400_HZ        0x0Cu
#define ADXL345_RATE_800_HZ        0x0Du
#define ADXL345_RATE_1600_HZ       0x0Eu
#define ADXL345_RATE_3200_HZ       0x0Fu

/*----------------------------------------------------------------------------
 * POWER_CTL register bits
 *----------------------------------------------------------------------------*/
#define ADXL345_POWER_CTL_LINK         (1u << 5)
#define ADXL345_POWER_CTL_AUTO_SLEEP   (1u << 4)
#define ADXL345_POWER_CTL_MEASURE      (1u << 3)
#define ADXL345_POWER_CTL_SLEEP        (1u << 2)
#define ADXL345_POWER_CTL_WAKEUP_MASK  0x03u

/*----------------------------------------------------------------------------
 * DATA_FORMAT register bits
 *----------------------------------------------------------------------------*/
#define ADXL345_DATA_FORMAT_SELF_TEST   (1u << 7)
#define ADXL345_DATA_FORMAT_SPI_3WIRE   (1u << 6)
#define ADXL345_DATA_FORMAT_INT_INVERT  (1u << 5)
#define ADXL345_DATA_FORMAT_FULL_RES    (1u << 3)
#define ADXL345_DATA_FORMAT_JUSTIFY     (1u << 2)
#define ADXL345_DATA_FORMAT_RANGE_MASK  0x03u

#define ADXL345_RANGE_2G                0x00u
#define ADXL345_RANGE_4G                0x01u
#define ADXL345_RANGE_8G                0x02u
#define ADXL345_RANGE_16G               0x03u

/*----------------------------------------------------------------------------
 * Simple status / error codes
 *----------------------------------------------------------------------------*/
typedef enum
{
    ADXL345_OK = 0,
    ADXL345_ERR_NULL_PTR = -1,
    ADXL345_ERR_DATA_FORMAT = -2,
    ADXL345_ERR_DEVID = -3
} adxl345_status_t;

/*----------------------------------------------------------------------------
 * Raw sample container
 *----------------------------------------------------------------------------*/
typedef struct
{
    int16_t x;
    int16_t y;
    int16_t z;
} adxl345_raw_xyz_t;

/*----------------------------------------------------------------------------
 * Basic register access API
 *----------------------------------------------------------------------------*/
adxl345_status_t adxl345_write_reg(uint8_t reg, uint8_t value);
adxl345_status_t adxl345_read_reg(uint8_t reg, uint8_t *value);
adxl345_status_t adxl345_read_regs(uint8_t start_reg, uint8_t *buf, uint32_t len);

/*----------------------------------------------------------------------------
 * Device-level helpers
 *----------------------------------------------------------------------------*/
adxl345_status_t adxl345_read_device_id(uint8_t *devid);
adxl345_status_t adxl345_set_bw_rate(uint8_t bw_rate);
adxl345_status_t adxl345_set_data_format(uint8_t data_format);
adxl345_status_t adxl345_set_measure(bool enable);
adxl345_status_t adxl345_read_xyz_raw(adxl345_raw_xyz_t *xyz);

/*----------------------------------------------------------------------------
 * Bring-up helper
 *
 * This follows the conservative known-good sequence:
 *   1) force DATA_FORMAT = 0x00 (4-wire, right-justified, +/-2g, no self-test)
 *   2) verify DATA_FORMAT readback
 *   3) verify DEVID == 0xE5
 *   4) set BW_RATE = 100 Hz
 *   5) set POWER_CTL.MEASURE = 1
 *----------------------------------------------------------------------------*/
adxl345_status_t adxl345_init_default(void);

#endif /* ADXL345_H */