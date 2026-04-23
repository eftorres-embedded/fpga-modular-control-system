#include "i2c_regs.h"

/*----------------------------------------------------------------------------
 * Internal timeout helper
 *----------------------------------------------------------------------------*/
static bool i2c_timeout_expired(uint32_t *remaining)
{
    if (*remaining == I2C_WAIT_FOREVER)
    {
        return false;
    }

    if (*remaining == 0u)
    {
        return true;
    }

    *remaining -= 1u;
    return false;
}

/*----------------------------------------------------------------------------
 * Internal helper
 *
 * After a command write, the engine should leave CMD_READY and later return to
 * CMD_READY when complete.
 *----------------------------------------------------------------------------*/
static i2c_status_t i2c_wait_cmd_accepted_and_completed_timeout(uint32_t timeout_poll_count)
{
    uint32_t remaining = timeout_poll_count;

    while (i2c_cmd_ready())
    {
        if (i2c_cmd_illegal())
        {
            return I2C_ERR_CMD_ILLEGAL;
        }

        if (i2c_timeout_expired(&remaining))
        {
            return I2C_ERR_TIMEOUT;
        }
    }

    while (!i2c_cmd_ready())
    {
        if (i2c_cmd_illegal())
        {
            return I2C_ERR_CMD_ILLEGAL;
        }

        if (i2c_timeout_expired(&remaining))
        {
            return I2C_ERR_TIMEOUT;
        }
    }

    if (i2c_cmd_illegal())
    {
        return I2C_ERR_CMD_ILLEGAL;
    }

    return I2C_OK;
}

/*----------------------------------------------------------------------------
 * Public API
 *----------------------------------------------------------------------------*/
void i2c_init(uint16_t divisor)
{
    i2c_write_divisor(divisor);
}

void i2c_wait_cmd_ready(void)
{
    (void)i2c_wait_cmd_ready_timeout(I2C_WAIT_FOREVER);
}

void i2c_wait_bus_idle(void)
{
    (void)i2c_wait_bus_idle_timeout(I2C_WAIT_FOREVER);
}

i2c_status_t i2c_wait_cmd_ready_timeout(uint32_t timeout_poll_count)
{
    uint32_t remaining = timeout_poll_count;

    while (!i2c_cmd_ready())
    {
        if (i2c_cmd_illegal())
        {
            return I2C_ERR_CMD_ILLEGAL;
        }

        if (i2c_timeout_expired(&remaining))
        {
            return I2C_ERR_TIMEOUT;
        }
    }

    return I2C_OK;
}

i2c_status_t i2c_wait_bus_idle_timeout(uint32_t timeout_poll_count)
{
    uint32_t remaining = timeout_poll_count;

    while (!i2c_bus_idle())
    {
        if (i2c_cmd_illegal())
        {
            return I2C_ERR_CMD_ILLEGAL;
        }

        if (i2c_timeout_expired(&remaining))
        {
            return I2C_ERR_TIMEOUT;
        }
    }

    return I2C_OK;
}

i2c_status_t i2c_launch_cmd_blocking(uint8_t cmd, bool rd_last)
{
    return i2c_launch_cmd_blocking_timeout(cmd, rd_last, I2C_WAIT_FOREVER);
}

i2c_status_t i2c_launch_cmd_blocking_timeout(uint8_t cmd,
                                             bool rd_last,
                                             uint32_t timeout_poll_count)
{
    i2c_status_t status;

    status = i2c_wait_cmd_ready_timeout(timeout_poll_count);
    if (status != I2C_OK)
    {
        return status;
    }

    i2c_write_cmd_raw(cmd, rd_last);

    return i2c_wait_cmd_accepted_and_completed_timeout(timeout_poll_count);
}

i2c_status_t i2c_start_blocking(void)
{
    return i2c_start_blocking_timeout(I2C_WAIT_FOREVER);
}

i2c_status_t i2c_start_blocking_timeout(uint32_t timeout_poll_count)
{
    return i2c_launch_cmd_blocking_timeout(I2C_CMD_START,
                                           false,
                                           timeout_poll_count);
}

i2c_status_t i2c_restart_blocking(void)
{
    return i2c_restart_blocking_timeout(I2C_WAIT_FOREVER);
}

i2c_status_t i2c_restart_blocking_timeout(uint32_t timeout_poll_count)
{
    return i2c_launch_cmd_blocking_timeout(I2C_CMD_RESTART,
                                           false,
                                           timeout_poll_count);
}

i2c_status_t i2c_stop_blocking(void)
{
    return i2c_stop_blocking_timeout(I2C_WAIT_FOREVER);
}

i2c_status_t i2c_stop_blocking_timeout(uint32_t timeout_poll_count)
{
    return i2c_launch_cmd_blocking_timeout(I2C_CMD_STOP,
                                           false,
                                           timeout_poll_count);
}

i2c_status_t i2c_write_byte_blocking(uint8_t data)
{
    return i2c_write_byte_blocking_timeout(data, I2C_WAIT_FOREVER);
}

i2c_status_t i2c_write_byte_blocking_timeout(uint8_t data,
                                             uint32_t timeout_poll_count)
{
    i2c_status_t status;

    status = i2c_wait_cmd_ready_timeout(timeout_poll_count);
    if (status != I2C_OK)
    {
        return status;
    }

    i2c_write_txdata(data);

    i2c_write_cmd_raw(I2C_CMD_WR, false);

    status = i2c_wait_cmd_accepted_and_completed_timeout(timeout_poll_count);
    if (status != I2C_OK)
    {
        return status;
    }

    if (i2c_nack_received())
    {
        return I2C_ERR_NACK;
    }

    return I2C_OK;
}

i2c_status_t i2c_read_byte_blocking(bool rd_last, uint8_t *data)
{
    return i2c_read_byte_blocking_timeout(rd_last, data, I2C_WAIT_FOREVER);
}

i2c_status_t i2c_read_byte_blocking_timeout(bool rd_last,
                                            uint8_t *data,
                                            uint32_t timeout_poll_count)
{
    i2c_status_t status;
    uint32_t remaining = timeout_poll_count;

    if (data == 0)
    {
        return I2C_ERR_NULL_PTR;
    }

    status = i2c_launch_cmd_blocking_timeout(I2C_CMD_RD,
                                             rd_last,
                                             timeout_poll_count);
    if (status != I2C_OK)
    {
        return status;
    }

    while (!i2c_rd_data_valid())
    {
        if (i2c_cmd_illegal())
        {
            return I2C_ERR_CMD_ILLEGAL;
        }

        if (i2c_timeout_expired(&remaining))
        {
            return I2C_ERR_TIMEOUT;
        }
    }

    *data = i2c_rxdata_read();
    return I2C_OK;
}

i2c_status_t i2c_write_addr7_blocking(uint8_t addr7, bool read)
{
    return i2c_write_addr7_blocking_timeout(addr7,
                                            read,
                                            I2C_WAIT_FOREVER);
}

i2c_status_t i2c_write_addr7_blocking_timeout(uint8_t addr7,
                                              bool read,
                                              uint32_t timeout_poll_count)
{
    uint8_t addr_byte;

    addr_byte = (uint8_t)(((addr7 & 0x7Fu) << 1) | (read ? 1u : 0u));

    return i2c_write_byte_blocking_timeout(addr_byte, timeout_poll_count);
}