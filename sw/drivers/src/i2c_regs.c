#include "i2c_regs.h"

#include <stddef.h>

/*----------------------------------------------------------------------------
 * Private timing / polling helpers
 *----------------------------------------------------------------------------*/
#define I2C_TIMEOUT_LOOPS   200000u

/*----------------------------------------------------------------------------
 * Private helpers
 *----------------------------------------------------------------------------*/

/* Return 8-bit write address from a 7-bit slave address. */
static uint8_t i2c_priv_addr_wr(uint8_t slave_address)
{
    return (uint8_t)((slave_address & 0x7Fu) << 1);
}

/* Return 8-bit read address from a 7-bit slave address. */
static uint8_t i2c_priv_addr_rd(uint8_t slave_address)
{
    return (uint8_t)(((slave_address & 0x7Fu) << 1) | 0x01u);
}

/* Return TX data-NACK error code for the given data-byte index. */
static uint8_t i2c_priv_data_nack_flag(uint8_t index)
{
    return (uint8_t)(I2C_TX_ERR_DATA_NACK_BASE + index);
}

/* Clear sticky completion/result bits in REG_STATUS. */
static void i2c_priv_clear_status_sticky(uint32_t base)
{
    uint32_t clear_mask;

    clear_mask =
        I2C_STATUS_DONE_MASK |
        I2C_STATUS_ACK_VALID_MASK |
        I2C_STATUS_ACK_MASK |
        I2C_STATUS_RD_DATA_VALID_MASK |
        I2C_STATUS_CMD_ILLEGAL_MASK;

    mmio_write32(base, I2C_REG_STATUS_OFFSET, clear_mask);
}

/* Wait until the core reports command-ready. */
static bool i2c_priv_wait_cmd_ready(uint32_t base)
{
    uint32_t i;

    for (i = 0u; i < I2C_TIMEOUT_LOOPS; i++)
    {
        if (i2c_status_cmd_ready(base))
        {
            return true;
        }
    }

    return false;
}

/* Wait until the core reports idle + ready. */
static bool i2c_priv_wait_idle_ready(uint32_t base)
{
    uint32_t i;

    for (i = 0u; i < I2C_TIMEOUT_LOOPS; i++)
    {
        if (i2c_status_cmd_ready(base) && i2c_bus_idle(base))
        {
            return true;
        }
    }

    return false;
}

/* Wait until the current byte command completes or an illegal-command condition appears. */
static bool i2c_priv_wait_cmd_cycle(uint32_t base)
{
    uint32_t i;
    uint32_t status;

    for (i = 0u; i < I2C_TIMEOUT_LOOPS; i++)
    {
        status = i2c_get_status(base);

        if ((status & I2C_STATUS_CMD_ILLEGAL_MASK) != 0u)
        {
            return false;
        }

        if ((status & I2C_STATUS_DONE_MASK) != 0u)
        {
            return true;
        }
    }

    return false;
}

/*
 * Best-effort recovery helper.
 *
 * Tries ABORT first because hardware is allowed to accept ABORT even when
 * cmd_ready is low. Then gives the core some time to return toward idle.
 */
static void i2c_priv_abort_to_idle(uint32_t base)
{
    uint32_t i;

    (void)i2c_cmd_abort(base);

    for (i = 0u; i < I2C_TIMEOUT_LOOPS; i++)
    {
        if (i2c_bus_idle(base) && i2c_status_cmd_ready(base))
        {
            break;
        }
    }
}

/*
 * Force the core toward IDLE as best as software can.
 *
 * Strategy:
 * 1) If already idle+ready, done.
 * 2) If ready but not idle, try STOP.
 * 3) If still not idle, try ABORT.
 * 4) Poll for idle+ready.
 *
 * This is intended for startup cleanup and error recovery.
 */
static void i2c_priv_force_idle(uint32_t base)
{
    if (i2c_status_cmd_ready(base) && i2c_bus_idle(base))
    {
        return;
    }

    if (i2c_status_cmd_ready(base) && !i2c_bus_idle(base))
    {
        i2c_priv_clear_status_sticky(base);
        (void)i2c_cmd_stop(base);
        (void)i2c_priv_wait_idle_ready(base);
    }

    if (!(i2c_status_cmd_ready(base) && i2c_bus_idle(base)))
    {
        i2c_priv_abort_to_idle(base);
    }

    (void)i2c_priv_wait_idle_ready(base);
}

/*
 * Write one byte during an already-started transaction and verify that:
 * - command completes
 * - ACK is valid
 * - ACK value indicates success
 *
 * Returns:
 * - I2C_TX_OK
 * - I2C_TX_ERR_CMD
 * - a caller-selected NACK code
 */
static uint8_t i2c_priv_write_phase_byte(uint32_t base,
                                         uint8_t data,
                                         uint8_t nack_code)
{
    uint8_t ack_info;

    if (!i2c_priv_wait_cmd_ready(base))
    {
        return I2C_TX_ERR_CMD;
    }

    i2c_priv_clear_status_sticky(base);
    i2c_write_txdata(base, data);

    if (i2c_cmd_wr(base))
    {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_cycle(base))
    {
        return I2C_TX_ERR_CMD;
    }

    ack_info = i2c_ack(base);

    if ((ack_info & 0x2u) == 0u)
    {
        return I2C_TX_ERR_CMD;
    }

    if ((ack_info & 0x1u) != 0u)
    {
        return nack_code;
    }

    return I2C_TX_OK;
}

/* Read one byte during an already-started transaction. */
static bool i2c_priv_read_phase_byte(uint32_t base, bool rd_last, uint8_t *data)
{
    if (data == NULL)
    {
        return false;
    }

    if (!i2c_priv_wait_cmd_ready(base))
    {
        return false;
    }

    i2c_priv_clear_status_sticky(base);

    if (i2c_cmd_rd(base, rd_last))
    {
        return false;
    }

    if (!i2c_priv_wait_cmd_cycle(base))
    {
        return false;
    }

    if (!i2c_rd_data_valid(base))
    {
        return false;
    }

    *data = i2c_read_rxdata(base);
    return true;
}

/*----------------------------------------------------------------------------
 * Mid-level command helpers
 *----------------------------------------------------------------------------*/

/* Send START and return true if the command was not accepted. */
bool i2c_cmd_start(uint32_t base)
{
    if (!i2c_status_cmd_ready(base))
    {
        return true;
    }

    i2c_write_cmd_raw(base, I2C_CMD_START, false, false);
    return false;
}

/* Send WRITE and return true if the command was not accepted. */
bool i2c_cmd_wr(uint32_t base)
{
    if (!i2c_status_cmd_ready(base))
    {
        return true;
    }

    i2c_write_cmd_raw(base, I2C_CMD_WR, false, false);
    return false;
}

/* Send READ with rd_last and return true if the command was not accepted. */
bool i2c_cmd_rd(uint32_t base, bool rd_last)
{
    if (!i2c_status_cmd_ready(base))
    {
        return true;
    }

    i2c_write_cmd_raw(base, I2C_CMD_RD, false, rd_last);
    return false;
}

/* Send STOP and return true if the command was not accepted. */
bool i2c_cmd_stop(uint32_t base)
{
    if (!i2c_status_cmd_ready(base))
    {
        return true;
    }

    i2c_write_cmd_raw(base, I2C_CMD_STOP, false, false);
    return false;
}

/* Send RESTART and return true if the command was not accepted. */
bool i2c_cmd_restart(uint32_t base)
{
    if (!i2c_status_cmd_ready(base))
    {
        return true;
    }

    i2c_write_cmd_raw(base, I2C_CMD_RESTART, false, false);
    return false;
}

/* Send ABORT and return true if the command write was not accepted. */
bool i2c_cmd_abort(uint32_t base)
{
    i2c_write_cmd_raw(base, I2C_CMD_START, true, false);
    return false;
}

/* Compute and program the I2C clock divisor from target bus frequency. */
void i2c_set_divisor(uint32_t base, uint16_t freq_kHz, uint8_t core_MHz)
{
    uint32_t numerator;
    uint32_t denominator;
    uint32_t divisor32;

    if ((freq_kHz == 0u) || (core_MHz == 0u))
    {
        i2c_write_divisor_raw(base, 1u);
        return;
    }

    numerator   = (uint32_t)core_MHz * 1000u;
    denominator = 4u * (uint32_t)freq_kHz;

    /* Ceiling divide so actual bus speed does not exceed the request. */
    divisor32 = (numerator + denominator - 1u) / denominator;

    if (divisor32 < 1u)
    {
        divisor32 = 1u;
    }

    if (divisor32 > 0xFFFFu)
    {
        divisor32 = 0xFFFFu;
    }

    i2c_write_divisor_raw(base, (uint16_t)divisor32);
}

/*----------------------------------------------------------------------------
 * Higher-level transaction helpers
 *----------------------------------------------------------------------------*/

/* Initialize one I2C instance using the requested I2C bus frequency and core clock. */
void i2c_init(uint32_t base, uint16_t freq_kHz, uint8_t core_MHz)
{
    i2c_set_divisor(base, freq_kHz, core_MHz);

    i2c_priv_clear_status_sticky(base);
    i2c_clear_all_faults(base);

    /* Best-effort startup cleanup so the core begins from IDLE if possible. */
    i2c_priv_force_idle(base);

    i2c_priv_clear_status_sticky(base);
    i2c_clear_all_faults(base);
}

/* Transmit one byte to a 7-bit slave address and return TX status flags. */
uint8_t i2c_tx_byte(uint32_t base, uint8_t slave_address, uint8_t data)
{
    uint8_t tx_buf[1];

    tx_buf[0] = data;
    return i2c_tx_buf(base, slave_address, tx_buf, 1u);
}

/* Transmit a null-terminated string to a 7-bit slave address and return TX status flags. */
uint8_t i2c_tx_pkg(uint32_t base, uint8_t slave_address, const char *msg)
{
    uint8_t status;
    uint8_t index;
    uint8_t data_byte;

    if (msg == NULL)
    {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_ready(base))
    {
        return I2C_TX_ERR_CMD;
    }

    i2c_priv_clear_status_sticky(base);

    if (i2c_cmd_start(base))
    {
        return I2C_TX_ERR_CMD;
    }

    /*
     * START completes by returning to HOLD:
     * cmd_ready=1 and bus_idle=0
     */
    if (!i2c_priv_wait_cmd_ready(base) || i2c_bus_idle(base))
    {
        i2c_priv_abort_to_idle(base);
        return I2C_TX_ERR_CMD;
    }

    status = i2c_priv_write_phase_byte(base,
                                       i2c_priv_addr_wr(slave_address),
                                       I2C_TX_ERR_ADDR_NACK);
    if (status != I2C_TX_OK)
    {
        i2c_priv_abort_to_idle(base);
        return status;
    }

    index = 0u;
    while (1)
    {
        data_byte = (uint8_t)msg[index];

        if (data_byte == '\0')
        {
            break;
        }

        status = i2c_priv_write_phase_byte(base,
                                           data_byte,
                                           i2c_priv_data_nack_flag(index));
        if (status != I2C_TX_OK)
        {
            i2c_priv_abort_to_idle(base);
            return status;
        }

        index++;
    }

    if (!i2c_priv_wait_cmd_ready(base))
    {
        i2c_priv_abort_to_idle(base);
        return I2C_TX_ERR_CMD;
    }

    i2c_priv_clear_status_sticky(base);

    if (i2c_cmd_stop(base))
    {
        i2c_priv_abort_to_idle(base);
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_idle_ready(base))
    {
        i2c_priv_abort_to_idle(base);
        return I2C_TX_ERR_CMD;
    }

    return I2C_TX_OK;
}

/* Transmit a raw byte buffer to a 7-bit slave address and return TX status flags. */
uint8_t i2c_tx_buf(uint32_t base, uint8_t slave_address, const uint8_t *data, uint8_t length)
{
    uint8_t status;
    uint8_t index;

    if ((data == NULL) && (length != 0u))
    {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_ready(base))
    {
        return I2C_TX_ERR_CMD;
    }

    i2c_priv_clear_status_sticky(base);

    if (i2c_cmd_start(base))
    {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_ready(base) || i2c_bus_idle(base))
    {
        i2c_priv_abort_to_idle(base);
        return I2C_TX_ERR_CMD;
    }

    status = i2c_priv_write_phase_byte(base,
                                       i2c_priv_addr_wr(slave_address),
                                       I2C_TX_ERR_ADDR_NACK);
    if (status != I2C_TX_OK)
    {
        i2c_priv_abort_to_idle(base);
        return status;
    }

    for (index = 0u; index < length; index++)
    {
        status = i2c_priv_write_phase_byte(base,
                                           data[index],
                                           i2c_priv_data_nack_flag(index));
        if (status != I2C_TX_OK)
        {
            i2c_priv_abort_to_idle(base);
            return status;
        }
    }

    if (!i2c_priv_wait_cmd_ready(base))
    {
        i2c_priv_abort_to_idle(base);
        return I2C_TX_ERR_CMD;
    }

    i2c_priv_clear_status_sticky(base);

    if (i2c_cmd_stop(base))
    {
        i2c_priv_abort_to_idle(base);
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_idle_ready(base))
    {
        i2c_priv_abort_to_idle(base);
        return I2C_TX_ERR_CMD;
    }

    return I2C_TX_OK;
}

/* Receive length bytes into buffer and return true on success. */
bool i2c_rx_pkg(uint32_t base, uint8_t slave_address, uint8_t *buffer, uint8_t length)
{
    uint8_t index;
    bool rd_last;

    if ((buffer == NULL) && (length != 0u))
    {
        return false;
    }

    if (length == 0u)
    {
        return true;
    }

    if (!i2c_priv_wait_cmd_ready(base))
    {
        return false;
    }

    i2c_priv_clear_status_sticky(base);

    if (i2c_cmd_start(base))
    {
        return false;
    }

    if (!i2c_priv_wait_cmd_ready(base) || i2c_bus_idle(base))
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    if (i2c_priv_write_phase_byte(base,
                                  i2c_priv_addr_rd(slave_address),
                                  I2C_TX_ERR_ADDR_NACK) != I2C_TX_OK)
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    for (index = 0u; index < length; index++)
    {
        rd_last = (index == (uint8_t)(length - 1u));

        if (!i2c_priv_read_phase_byte(base, rd_last, &buffer[index]))
        {
            i2c_priv_abort_to_idle(base);
            return false;
        }
    }

    if (!i2c_priv_wait_cmd_ready(base))
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    i2c_priv_clear_status_sticky(base);

    if (i2c_cmd_stop(base))
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    if (!i2c_priv_wait_idle_ready(base))
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    return true;
}

/* Receive one byte into *data and return true on success. */
bool i2c_rx_byte(uint32_t base, uint8_t slave_address, uint8_t *data)
{
    return i2c_rx_pkg(base, slave_address, data, 1u);
}

/* Transmit tx_len bytes, then issue RESTART and receive rx_len bytes from a 7-bit slave address, returning true on success. */
bool i2c_txrx_buf(uint32_t base,
                  uint8_t slave_address,
                  const uint8_t *tx_data,
                  uint8_t tx_len,
                  uint8_t *rx_data,
                  uint8_t rx_len)
{
    uint8_t index;
    bool rd_last;

    if ((tx_data == NULL) && (tx_len != 0u))
    {
        return false;
    }

    if ((rx_data == NULL) && (rx_len != 0u))
    {
        return false;
    }

    if (!i2c_priv_wait_cmd_ready(base))
    {
        return false;
    }

    i2c_priv_clear_status_sticky(base);

    if (i2c_cmd_start(base))
    {
        return false;
    }

    if (!i2c_priv_wait_cmd_ready(base) || i2c_bus_idle(base))
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    if (i2c_priv_write_phase_byte(base,
                                  i2c_priv_addr_wr(slave_address),
                                  I2C_TX_ERR_ADDR_NACK) != I2C_TX_OK)
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    for (index = 0u; index < tx_len; index++)
    {
        if (i2c_priv_write_phase_byte(base,
                                      tx_data[index],
                                      i2c_priv_data_nack_flag(index)) != I2C_TX_OK)
        {
            i2c_priv_abort_to_idle(base);
            return false;
        }
    }

    if (rx_len != 0u)
    {
        if (!i2c_priv_wait_cmd_ready(base))
        {
            i2c_priv_abort_to_idle(base);
            return false;
        }

        i2c_priv_clear_status_sticky(base);

        if (i2c_cmd_restart(base))
        {
            i2c_priv_abort_to_idle(base);
            return false;
        }

        if (!i2c_priv_wait_cmd_ready(base) || i2c_bus_idle(base))
        {
            i2c_priv_abort_to_idle(base);
            return false;
        }

        if (i2c_priv_write_phase_byte(base,
                                      i2c_priv_addr_rd(slave_address),
                                      I2C_TX_ERR_ADDR_NACK) != I2C_TX_OK)
        {
            i2c_priv_abort_to_idle(base);
            return false;
        }

        for (index = 0u; index < rx_len; index++)
        {
            rd_last = (index == (uint8_t)(rx_len - 1u));

            if (!i2c_priv_read_phase_byte(base, rd_last, &rx_data[index]))
            {
                i2c_priv_abort_to_idle(base);
                return false;
            }
        }
    }

    if (!i2c_priv_wait_cmd_ready(base))
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    i2c_priv_clear_status_sticky(base);

    if (i2c_cmd_stop(base))
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    if (!i2c_priv_wait_idle_ready(base))
    {
        i2c_priv_abort_to_idle(base);
        return false;
    }

    return true;
}