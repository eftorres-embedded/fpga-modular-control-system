#include "i2c_regs.h"

/*----------------------------------------------------------------------------
 * Basic init
 *----------------------------------------------------------------------------*/
void i2c_init(uint16_t divisor)
{
    i2c_write_divisor(divisor);
}

/*----------------------------------------------------------------------------
 * Polling helpers
 *----------------------------------------------------------------------------*/
void i2c_wait_cmd_ready(void)
{
    while (!i2c_cmd_ready()) {
    }
}

void i2c_wait_bus_idle(void)
{
    while (!i2c_bus_idle()) {
    }
}

/*----------------------------------------------------------------------------
 * Launch one command and wait until the core is ready again.
 *
 * Notes:
 * - REG_CMD is an action register, not retained state.
 * - Software must only launch while cmd_ready = 1.
 * - Because this wrapper is polling-first, we use cmd_ready returning high as
 *   the primary completion condition.
 *----------------------------------------------------------------------------*/
i2c_status_t i2c_launch_cmd_blocking(uint8_t cmd, bool rd_last)
{
    i2c_wait_cmd_ready();
    i2c_write_cmd_raw(cmd, rd_last);
    i2c_wait_cmd_ready();

    if (i2c_cmd_illegal()) {
        return I2C_ERR_CMD_ILLEGAL;
    }

    return I2C_OK;
}

i2c_status_t i2c_start_blocking(void)
{
    return i2c_launch_cmd_blocking(I2C_CMD_START, false);
}

i2c_status_t i2c_restart_blocking(void)
{
    return i2c_launch_cmd_blocking(I2C_CMD_RESTART, false);
}

i2c_status_t i2c_stop_blocking(void)
{
    return i2c_launch_cmd_blocking(I2C_CMD_STOP, false);
}

/*----------------------------------------------------------------------------
 * Blocking byte write
 *----------------------------------------------------------------------------*/
i2c_status_t i2c_write_byte_blocking(uint8_t data)
{
    i2c_write_txdata(data);
    return i2c_launch_cmd_blocking(I2C_CMD_WR, false);
}

/*----------------------------------------------------------------------------
 * Blocking byte read
 *
 * rd_last = true should be used on the final read byte so the core can NACK
 * the last byte appropriately.
 *----------------------------------------------------------------------------*/
i2c_status_t i2c_read_byte_blocking(bool rd_last, uint8_t *data)
{
    i2c_status_t st;

    if (data == 0) {
        return I2C_ERR_NULL_PTR;
    }

    st = i2c_launch_cmd_blocking(I2C_CMD_RD, rd_last);
    if (st != I2C_OK) {
        return st;
    }

    *data = i2c_rxdata_read();
    return I2C_OK;
}

/*----------------------------------------------------------------------------
 * Write a 7-bit I2C address byte.
 *
 * addr7 is the plain 7-bit address.
 * read=false -> write transfer address byte
 * read=true  -> read  transfer address byte
 *----------------------------------------------------------------------------*/
i2c_status_t i2c_write_addr7_blocking(uint8_t addr7, bool read)
{
    uint8_t addr_byte = (uint8_t)(((addr7 & 0x7Fu) << 1) | (read ? 1u : 0u));
    return i2c_write_byte_blocking(addr_byte);
}
