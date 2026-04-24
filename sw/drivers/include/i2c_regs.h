#ifndef I2C_REGS_H
#define I2C_REGS_H

#include <stdint.h>
#include <stdbool.h>

#include "user_define_system.h"
#include "mmio.h"

/*----------------------------------------------------------------------------
 * I2C instance aliases
 *----------------------------------------------------------------------------*/
#ifndef I2C_0_BASE
#define I2C_0_BASE   I2C_BASE
#endif

/*----------------------------------------------------------------------------
 * I2C register offsets
 *----------------------------------------------------------------------------*/
#define I2C_REG_STATUS_OFFSET      0x00u
#define I2C_REG_DIVISOR_OFFSET     0x04u
#define I2C_REG_TXDATA_OFFSET      0x08u
#define I2C_REG_RXDATA_OFFSET      0x0Cu
#define I2C_REG_CMD_OFFSET         0x10u

/*----------------------------------------------------------------------------
 * REG_STATUS bit positions
 *----------------------------------------------------------------------------*/
#define I2C_STATUS_CMD_READY_BIT         0u
#define I2C_STATUS_BUS_IDLE_BIT          1u
#define I2C_STATUS_DONE_BIT              2u
#define I2C_STATUS_ACK_VALID_BIT         3u
#define I2C_STATUS_ACK_BIT               4u
#define I2C_STATUS_RD_DATA_VALID_BIT     5u
#define I2C_STATUS_CMD_ILLEGAL_BIT       6u
#define I2C_STATUS_MASTER_RECEIVING_BIT  7u

/*----------------------------------------------------------------------------
 * REG_STATUS bit masks
 *----------------------------------------------------------------------------*/
#define I2C_STATUS_CMD_READY_MASK         (1u << I2C_STATUS_CMD_READY_BIT)
#define I2C_STATUS_BUS_IDLE_MASK          (1u << I2C_STATUS_BUS_IDLE_BIT)
#define I2C_STATUS_DONE_MASK              (1u << I2C_STATUS_DONE_BIT)
#define I2C_STATUS_ACK_VALID_MASK         (1u << I2C_STATUS_ACK_VALID_BIT)
#define I2C_STATUS_ACK_MASK               (1u << I2C_STATUS_ACK_BIT)
#define I2C_STATUS_RD_DATA_VALID_MASK     (1u << I2C_STATUS_RD_DATA_VALID_BIT)
#define I2C_STATUS_CMD_ILLEGAL_MASK       (1u << I2C_STATUS_CMD_ILLEGAL_BIT)
#define I2C_STATUS_MASTER_RECEIVING_MASK  (1u << I2C_STATUS_MASTER_RECEIVING_BIT)

/*----------------------------------------------------------------------------
 * REG_CMD encoding
 *
 * REG_CMD[2:0] = command
 * REG_CMD[8]   = rd_last
 *----------------------------------------------------------------------------*/
#define I2C_CMD_START        0u
#define I2C_CMD_WR           1u
#define I2C_CMD_RD           2u
#define I2C_CMD_STOP         3u
#define I2C_CMD_RESTART      4u

#define I2C_CMD_FIELD_MASK   0x7u
#define I2C_CMD_RD_LAST_BIT  8u
#define I2C_CMD_RD_LAST_MASK (1u << I2C_CMD_RD_LAST_BIT)

/*----------------------------------------------------------------------------
 * TX status flag encoding
 *----------------------------------------------------------------------------*/
#define I2C_TX_OK                  0u
#define I2C_TX_ERR_CMD             1u
#define I2C_TX_ERR_ADDR_NACK       2u
#define I2C_TX_ERR_DATA_NACK_BASE  3u

/*----------------------------------------------------------------------------
 * Low-level inline helpers
 *
 * These are simple MMIO accessors and bit decoders only.
 * Command helpers and higher-level transaction helpers are declared below
 * and should be implemented in i2c_regs.c.
 *----------------------------------------------------------------------------*/

/* Read and return the raw 32-bit I2C status register. */
static inline uint32_t i2c_get_status(uint32_t base)
{
    return mmio_read32(base, I2C_REG_STATUS_OFFSET);
}

/* Write the raw 16-bit divider value into REG_DIVISOR. */
static inline void i2c_write_divisor_raw(uint32_t base, uint16_t divisor)
{
    mmio_write32(base, I2C_REG_DIVISOR_OFFSET, (uint32_t)divisor);
}

/* Write one transmit byte into REG_TXDATA. */
static inline void i2c_write_txdata(uint32_t base, uint8_t data)
{
    mmio_write32(base, I2C_REG_TXDATA_OFFSET, (uint32_t)data);
}

/* Read and return the low 8 bits from REG_RXDATA. */
static inline uint8_t i2c_read_rxdata(uint32_t base)
{
    return (uint8_t)(mmio_read32(base, I2C_REG_RXDATA_OFFSET) & 0xFFu);
}

/* Return true when the core is ready to accept a new command. */
static inline bool i2c_status_cmd_ready(uint32_t base)
{
    return (i2c_get_status(base) & I2C_STATUS_CMD_READY_MASK) != 0u;
}

/* Return true when the current command has completed. */
static inline bool i2c_status_done(uint32_t base)
{
    return (i2c_get_status(base) & I2C_STATUS_DONE_MASK) != 0u;
}

/* Return true when the I2C bus is currently idle. */
static inline bool i2c_bus_idle(uint32_t base)
{
    return (i2c_get_status(base) & I2C_STATUS_BUS_IDLE_MASK) != 0u;
}

/* Return true when a received data byte is available in REG_RXDATA. */
static inline bool i2c_rd_data_valid(uint32_t base)
{
    return (i2c_get_status(base) & I2C_STATUS_RD_DATA_VALID_MASK) != 0u;
}

/* Return true when the hardware reports an illegal command condition. */
static inline bool i2c_cmd_illegal(uint32_t base)
{
    return (i2c_get_status(base) & I2C_STATUS_CMD_ILLEGAL_MASK) != 0u;
}

/* Return ACK info packed as bit1=valid and bit0=ack value. */
static inline uint8_t i2c_ack(uint32_t base)
{
    uint32_t status = i2c_get_status(base);
    uint8_t ack_valid = (uint8_t)((status >> I2C_STATUS_ACK_VALID_BIT) & 0x1u);
    uint8_t ack_value = (uint8_t)((status >> I2C_STATUS_ACK_BIT) & 0x1u);

    return (uint8_t)((ack_valid << 1) | ack_value);
}

/* Pack a REG_CMD word from command code and rd_last flag. */
static inline uint32_t i2c_pack_cmd(uint8_t cmd, bool rd_last)
{
    uint32_t value = ((uint32_t)cmd & I2C_CMD_FIELD_MASK);

    if (rd_last) {
        value |= I2C_CMD_RD_LAST_MASK;
    }

    return value;
}

/* Write a raw command word into REG_CMD. */
static inline void i2c_write_cmd_raw(uint32_t base, uint8_t cmd, bool rd_last)
{
    mmio_write32(base, I2C_REG_CMD_OFFSET, i2c_pack_cmd(cmd, rd_last));
}

/*----------------------------------------------------------------------------
 * Mid-level command helpers
 *----------------------------------------------------------------------------*/

/* Send START and return true if the command was not accepted. */
bool i2c_cmd_start(uint32_t base);

/* Send WRITE and return true if the command was not accepted. */
bool i2c_cmd_wr(uint32_t base);

/* Send READ with rd_last and return true if the command was not accepted. */
bool i2c_cmd_rd(uint32_t base, bool rd_last);

/* Send STOP and return true if the command was not accepted. */
bool i2c_cmd_stop(uint32_t base);

/* Send RESTART and return true if the command was not accepted. */
bool i2c_cmd_restart(uint32_t base);

/* Compute and program the I2C clock divisor from target bus frequency. */
void i2c_set_divisor(uint32_t base, uint16_t freq_kHz, uint8_t core_MHz);

/*----------------------------------------------------------------------------
 * Higher-level transaction helpers
 *----------------------------------------------------------------------------*/

/* Initialize one I2C instance using the requested I2C bus frequency and core clock. */
void i2c_init(uint32_t base, uint16_t freq_kHz, uint8_t core_MHz);

/* Transmit one byte to a 7-bit slave address and return TX status flags. */
uint8_t i2c_tx_byte(uint32_t base, uint8_t slave_address, uint8_t data);

/* Transmit a null-terminated string to a 7-bit slave address and return TX status flags. */
uint8_t i2c_tx_pkg(uint32_t base, uint8_t slave_address, const char *msg);

/* Transmit a raw byte buffer to a 7-bit slave address and return TX status flags. */
uint8_t i2c_tx_buf(uint32_t base, uint8_t slave_address, const uint8_t *data, uint8_t length);

/* Receive length bytes into buffer and return true on success. */
bool i2c_rx_pkg(uint32_t base, uint8_t slave_address, uint8_t *buffer, uint8_t length);

/* Receive one byte into *data and return true on success. */
bool i2c_rx_byte(uint32_t base, uint8_t slave_address, uint8_t *data);

/* Transmit tx_len bytes, then issue RESTART and receive rx_len bytes from a 7-bit slave address, returning true on success. */
bool i2c_txrx_buf(uint32_t base,
                  uint8_t slave_address,
                  const uint8_t *tx_data,
                  uint8_t tx_len,
                  uint8_t *rx_data,
                  uint8_t rx_len);

#endif /* I2C_REGS_H */