#ifndef I2C_REGS_H
#define I2C_REGS_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include "system.h"

/*----------------------------------------------------------------------------
 * Base-address mapping
 *
 * Prefer the BSP-generated system.h macro if it exists.
 * Fallback keeps bring-up easy if the generated name changes.
 *----------------------------------------------------------------------------*/
#ifndef I2C_BASE_ADDR
    #if defined(I2C_REGS_0_BASE)
        #define I2C_BASE_ADDR I2C_REGS_0_BASE
    #elif defined(I2C_MASTER_0_BASE)
        #define I2C_BASE_ADDR I2C_MASTER_0_BASE
    #elif defined(I2C_0_BASE)
        #define I2C_BASE_ADDR I2C_0_BASE
    #else
        #define I2C_BASE_ADDR 0x00034000u
    #endif
#endif

/*----------------------------------------------------------------------------
 * Register offsets
 *----------------------------------------------------------------------------*/
#define I2C_REG_STATUS_OFFSET       0x00u
#define I2C_REG_DIVISOR_OFFSET      0x04u
#define I2C_REG_TXDATA_OFFSET       0x08u
#define I2C_REG_RXDATA_OFFSET       0x0Cu
#define I2C_REG_CMD_OFFSET          0x10u

/*----------------------------------------------------------------------------
 * Absolute register addresses
 *----------------------------------------------------------------------------*/
#define I2C_REG_STATUS_ADDR         (I2C_BASE_ADDR + I2C_REG_STATUS_OFFSET)
#define I2C_REG_DIVISOR_ADDR        (I2C_BASE_ADDR + I2C_REG_DIVISOR_OFFSET)
#define I2C_REG_TXDATA_ADDR         (I2C_BASE_ADDR + I2C_REG_TXDATA_OFFSET)
#define I2C_REG_RXDATA_ADDR         (I2C_BASE_ADDR + I2C_REG_RXDATA_OFFSET)
#define I2C_REG_CMD_ADDR            (I2C_BASE_ADDR + I2C_REG_CMD_OFFSET)

/*----------------------------------------------------------------------------
 * Register access macros
 *----------------------------------------------------------------------------*/
#define I2C_REG_STATUS              (*(volatile uint32_t *)(uintptr_t)(I2C_REG_STATUS_ADDR))
#define I2C_REG_DIVISOR             (*(volatile uint32_t *)(uintptr_t)(I2C_REG_DIVISOR_ADDR))
#define I2C_REG_TXDATA              (*(volatile uint32_t *)(uintptr_t)(I2C_REG_TXDATA_ADDR))
#define I2C_REG_RXDATA              (*(volatile uint32_t *)(uintptr_t)(I2C_REG_RXDATA_ADDR))
#define I2C_REG_CMD                 (*(volatile uint32_t *)(uintptr_t)(I2C_REG_CMD_ADDR))

/*----------------------------------------------------------------------------
 * STATUS register bits
 *----------------------------------------------------------------------------*/
#define I2C_STATUS_CMD_READY_BIT        0u
#define I2C_STATUS_BUS_IDLE_BIT         1u
#define I2C_STATUS_DONE_TICK_BIT        2u
#define I2C_STATUS_ACK_VALID_BIT        3u
#define I2C_STATUS_ACK_BIT              4u
#define I2C_STATUS_RD_DATA_VALID_BIT    5u
#define I2C_STATUS_CMD_ILLEGAL_BIT      6u
#define I2C_STATUS_MASTER_RX_BIT        7u

#define I2C_STATUS_CMD_READY        (1u << I2C_STATUS_CMD_READY_BIT)
#define I2C_STATUS_BUS_IDLE         (1u << I2C_STATUS_BUS_IDLE_BIT)
#define I2C_STATUS_DONE_TICK        (1u << I2C_STATUS_DONE_TICK_BIT)
#define I2C_STATUS_ACK_VALID        (1u << I2C_STATUS_ACK_VALID_BIT)
#define I2C_STATUS_ACK              (1u << I2C_STATUS_ACK_BIT)
#define I2C_STATUS_RD_DATA_VALID    (1u << I2C_STATUS_RD_DATA_VALID_BIT)
#define I2C_STATUS_CMD_ILLEGAL      (1u << I2C_STATUS_CMD_ILLEGAL_BIT)
#define I2C_STATUS_MASTER_RX        (1u << I2C_STATUS_MASTER_RX_BIT)

/*----------------------------------------------------------------------------
 * REG_CMD encodings
 *----------------------------------------------------------------------------*/
#define I2C_CMD_W_FIELD_MASK        0x07u
#define I2C_CMD_RD_LAST_BIT         8u
#define I2C_CMD_RD_LAST             (1u << I2C_CMD_RD_LAST_BIT)

#define I2C_CMD_START               0x0u
#define I2C_CMD_WR                  0x1u
#define I2C_CMD_RD                  0x2u
#define I2C_CMD_STOP                0x3u
#define I2C_CMD_RESTART             0x4u

/*----------------------------------------------------------------------------
 * Small status / error codes
 *----------------------------------------------------------------------------*/
typedef enum
{
    I2C_OK = 0,
    I2C_ERR_NULL_PTR = -1,
    I2C_ERR_CMD_ILLEGAL = -2
} i2c_status_t;

/*----------------------------------------------------------------------------
 * Low-level MMIO helpers
 *----------------------------------------------------------------------------*/
static inline uint32_t i2c_status_read(void)       { return I2C_REG_STATUS; }
static inline uint16_t i2c_divisor_read(void)      { return (uint16_t)(I2C_REG_DIVISOR & 0xFFFFu); }
static inline uint8_t  i2c_txdata_read(void)       { return (uint8_t)(I2C_REG_TXDATA & 0xFFu); }
static inline uint8_t  i2c_rxdata_read(void)       { return (uint8_t)(I2C_REG_RXDATA & 0xFFu); }

static inline bool i2c_cmd_ready(void)             { return (I2C_REG_STATUS & I2C_STATUS_CMD_READY) != 0u; }
static inline bool i2c_bus_idle(void)              { return (I2C_REG_STATUS & I2C_STATUS_BUS_IDLE) != 0u; }
static inline bool i2c_done_tick(void)             { return (I2C_REG_STATUS & I2C_STATUS_DONE_TICK) != 0u; }
static inline bool i2c_ack_valid(void)             { return (I2C_REG_STATUS & I2C_STATUS_ACK_VALID) != 0u; }
static inline bool i2c_ack_sample(void)            { return (I2C_REG_STATUS & I2C_STATUS_ACK) != 0u; }
static inline bool i2c_rd_data_valid(void)         { return (I2C_REG_STATUS & I2C_STATUS_RD_DATA_VALID) != 0u; }
static inline bool i2c_cmd_illegal(void)           { return (I2C_REG_STATUS & I2C_STATUS_CMD_ILLEGAL) != 0u; }
static inline bool i2c_master_receiving(void)      { return (I2C_REG_STATUS & I2C_STATUS_MASTER_RX) != 0u; }

static inline void i2c_write_divisor(uint16_t d)   { I2C_REG_DIVISOR = (uint32_t)d; }
static inline void i2c_write_txdata(uint8_t data)  { I2C_REG_TXDATA = (uint32_t)data; }
static inline void i2c_write_cmd_raw(uint8_t cmd, bool rd_last)
{
    uint32_t value = ((uint32_t)cmd & I2C_CMD_W_FIELD_MASK) |
                     (rd_last ? I2C_CMD_RD_LAST : 0u);
    I2C_REG_CMD = value;
}

/*----------------------------------------------------------------------------
 * Driver API implemented in i2c_regs.c
 *----------------------------------------------------------------------------*/
void i2c_init(uint16_t divisor);
void i2c_wait_cmd_ready(void);
void i2c_wait_bus_idle(void);

i2c_status_t i2c_launch_cmd_blocking(uint8_t cmd, bool rd_last);
i2c_status_t i2c_start_blocking(void);
i2c_status_t i2c_restart_blocking(void);
i2c_status_t i2c_stop_blocking(void);
i2c_status_t i2c_write_byte_blocking(uint8_t data);
i2c_status_t i2c_read_byte_blocking(bool rd_last, uint8_t *data);
i2c_status_t i2c_write_addr7_blocking(uint8_t addr7, bool read);

#endif /* I2C_REGS_H */
