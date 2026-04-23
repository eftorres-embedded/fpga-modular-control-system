#include "i2c_xfer.h"

/*----------------------------------------------------------------------------
 * Internal helper
 *
 * On error, try to release the bus with STOP, but preserve the original error.
 *----------------------------------------------------------------------------*/
static i2c_status_t i2c_finish_with_stop(i2c_status_t status,
                                         uint32_t timeout_poll_count)
{
    i2c_status_t stop_status;

    stop_status = i2c_stop_blocking_timeout(timeout_poll_count);

    if (status != I2C_OK)
    {
        return status;
    }

    return stop_status;
}

/*----------------------------------------------------------------------------
 * Raw device transfers
 *----------------------------------------------------------------------------*/
i2c_status_t i2c_write_bytes(uint8_t addr7,
                             const uint8_t *data,
                             size_t len)
{
    return i2c_write_bytes_timeout(addr7,
                                   data,
                                   len,
                                   I2C_WAIT_FOREVER);
}

i2c_status_t i2c_write_bytes_timeout(uint8_t addr7,
                                     const uint8_t *data,
                                     size_t len,
                                     uint32_t timeout_poll_count)
{
    i2c_status_t status;
    size_t i;

    if ((data == NULL) && (len != 0u))
    {
        return I2C_ERR_NULL_PTR;
    }

    status = i2c_start_blocking_timeout(timeout_poll_count);
    if (status != I2C_OK)
    {
        return status;
    }

    status = i2c_write_addr7_blocking_timeout(addr7,
                                              false,
                                              timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    for (i = 0; i < len; ++i)
    {
        status = i2c_write_byte_blocking_timeout(data[i],
                                                 timeout_poll_count);
        if (status != I2C_OK)
        {
            return i2c_finish_with_stop(status, timeout_poll_count);
        }
    }

    return i2c_finish_with_stop(I2C_OK, timeout_poll_count);
}

i2c_status_t i2c_read_bytes(uint8_t addr7,
                            uint8_t *data,
                            size_t len)
{
    return i2c_read_bytes_timeout(addr7,
                                  data,
                                  len,
                                  I2C_WAIT_FOREVER);
}

i2c_status_t i2c_read_bytes_timeout(uint8_t addr7,
                                    uint8_t *data,
                                    size_t len,
                                    uint32_t timeout_poll_count)
{
    i2c_status_t status;
    size_t i;

    if ((data == NULL) && (len != 0u))
    {
        return I2C_ERR_NULL_PTR;
    }

    status = i2c_start_blocking_timeout(timeout_poll_count);
    if (status != I2C_OK)
    {
        return status;
    }

    status = i2c_write_addr7_blocking_timeout(addr7,
                                              true,
                                              timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    for (i = 0; i < len; ++i)
    {
        bool rd_last = (i == (len - 1u));

        status = i2c_read_byte_blocking_timeout(rd_last,
                                                &data[i],
                                                timeout_poll_count);
        if (status != I2C_OK)
        {
            return i2c_finish_with_stop(status, timeout_poll_count);
        }
    }

    return i2c_finish_with_stop(I2C_OK, timeout_poll_count);
}

/*----------------------------------------------------------------------------
 * Common register-style transfers
 *----------------------------------------------------------------------------*/
i2c_status_t i2c_reg_write8(uint8_t addr7,
                            uint8_t reg,
                            uint8_t value)
{
    return i2c_reg_write8_timeout(addr7,
                                  reg,
                                  value,
                                  I2C_WAIT_FOREVER);
}

i2c_status_t i2c_reg_write8_timeout(uint8_t addr7,
                                    uint8_t reg,
                                    uint8_t value,
                                    uint32_t timeout_poll_count)
{
    i2c_status_t status;

    status = i2c_start_blocking_timeout(timeout_poll_count);
    if (status != I2C_OK)
    {
        return status;
    }

    status = i2c_write_addr7_blocking_timeout(addr7,
                                              false,
                                              timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    status = i2c_write_byte_blocking_timeout(reg, timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    status = i2c_write_byte_blocking_timeout(value, timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    return i2c_finish_with_stop(I2C_OK, timeout_poll_count);
}

i2c_status_t i2c_reg_read8(uint8_t addr7,
                           uint8_t reg,
                           uint8_t *value)
{
    return i2c_reg_read8_timeout(addr7,
                                 reg,
                                 value,
                                 I2C_WAIT_FOREVER);
}

i2c_status_t i2c_reg_read8_timeout(uint8_t addr7,
                                   uint8_t reg,
                                   uint8_t *value,
                                   uint32_t timeout_poll_count)
{
    return i2c_reg_read_bytes_timeout(addr7,
                                      reg,
                                      value,
                                      1u,
                                      timeout_poll_count);
}

i2c_status_t i2c_reg_write_bytes(uint8_t addr7,
                                 uint8_t reg,
                                 const uint8_t *data,
                                 size_t len)
{
    return i2c_reg_write_bytes_timeout(addr7,
                                       reg,
                                       data,
                                       len,
                                       I2C_WAIT_FOREVER);
}

i2c_status_t i2c_reg_write_bytes_timeout(uint8_t addr7,
                                         uint8_t reg,
                                         const uint8_t *data,
                                         size_t len,
                                         uint32_t timeout_poll_count)
{
    i2c_status_t status;
    size_t i;

    if ((data == NULL) && (len != 0u))
    {
        return I2C_ERR_NULL_PTR;
    }

    status = i2c_start_blocking_timeout(timeout_poll_count);
    if (status != I2C_OK)
    {
        return status;
    }

    status = i2c_write_addr7_blocking_timeout(addr7,
                                              false,
                                              timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    status = i2c_write_byte_blocking_timeout(reg, timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    for (i = 0; i < len; ++i)
    {
        status = i2c_write_byte_blocking_timeout(data[i],
                                                 timeout_poll_count);
        if (status != I2C_OK)
        {
            return i2c_finish_with_stop(status, timeout_poll_count);
        }
    }

    return i2c_finish_with_stop(I2C_OK, timeout_poll_count);
}

i2c_status_t i2c_reg_read_bytes(uint8_t addr7,
                                uint8_t reg,
                                uint8_t *data,
                                size_t len)
{
    return i2c_reg_read_bytes_timeout(addr7,
                                      reg,
                                      data,
                                      len,
                                      I2C_WAIT_FOREVER);
}

i2c_status_t i2c_reg_read_bytes_timeout(uint8_t addr7,
                                        uint8_t reg,
                                        uint8_t *data,
                                        size_t len,
                                        uint32_t timeout_poll_count)
{
    i2c_status_t status;
    size_t i;

    if ((data == NULL) && (len != 0u))
    {
        return I2C_ERR_NULL_PTR;
    }

    status = i2c_start_blocking_timeout(timeout_poll_count);
    if (status != I2C_OK)
    {
        return status;
    }

    status = i2c_write_addr7_blocking_timeout(addr7,
                                              false,
                                              timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    status = i2c_write_byte_blocking_timeout(reg, timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    status = i2c_restart_blocking_timeout(timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    status = i2c_write_addr7_blocking_timeout(addr7,
                                              true,
                                              timeout_poll_count);
    if (status != I2C_OK)
    {
        return i2c_finish_with_stop(status, timeout_poll_count);
    }

    for (i = 0; i < len; ++i)
    {
        bool rd_last = (i == (len - 1u));

        status = i2c_read_byte_blocking_timeout(rd_last,
                                                &data[i],
                                                timeout_poll_count);
        if (status != I2C_OK)
        {
            return i2c_finish_with_stop(status, timeout_poll_count);
        }
    }

    return i2c_finish_with_stop(I2C_OK, timeout_poll_count);
}