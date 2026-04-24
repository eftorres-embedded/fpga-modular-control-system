#include "i2c_regs.h"

/*----------------------------------------------------------------------------
 * Internal polling limits
 *----------------------------------------------------------------------------*/
#define I2C_POLL_LIMIT               1000000u
#define I2C_TX_ERR_DATA_NACK_SAT     0xFFu

/*----------------------------------------------------------------------------
 * Private helpers
 *----------------------------------------------------------------------------*/

/* Try to launch a low-level command and return true if the launch was rejected. */
static bool i2c_priv_issue_cmd(uint32_t base, uint8_t cmd, bool rd_last)
{
    if (!i2c_status_cmd_ready(base)) {
        return true;
    }

    i2c_write_cmd_raw(base, cmd, rd_last);
    return false;
}

/* Wait until cmd_ready becomes true. */
static bool i2c_priv_wait_cmd_ready(uint32_t base)
{
    uint32_t i;

    for (i = 0u; i < I2C_POLL_LIMIT; i++) {
        if (i2c_status_cmd_ready(base)) {
            return true;
        }
    }

    return false;
}

/* Wait until done becomes true. */
static bool i2c_priv_wait_done(uint32_t base)
{
    uint32_t i;

    for (i = 0u; i < I2C_POLL_LIMIT; i++) {
        if (i2c_status_done(base)) {
            return true;
        }
    }

    return false;
}

/* Wait until rd_data_valid becomes true. */
static bool i2c_priv_wait_rd_valid(uint32_t base)
{
    uint32_t i;

    for (i = 0u; i < I2C_POLL_LIMIT; i++) {
        if (i2c_rd_data_valid(base)) {
            return true;
        }
    }

    return false;
}

/*
 * Wait for a non-data command to complete by observing cmd_ready
 * go low and then high again.
 */
static bool i2c_priv_wait_cmd_cycle(uint32_t base)
{
    uint32_t i;
    bool saw_busy = false;

    for (i = 0u; i < I2C_POLL_LIMIT; i++) {
        if (!i2c_status_cmd_ready(base)) {
            saw_busy = true;
        } else if (saw_busy) {
            return true;
        }
    }

    return false;
}

/* Build address byte for write phase from a 7-bit slave address. */
static uint8_t i2c_priv_addr_wr(uint8_t slave_address)
{
    return (uint8_t)(((slave_address & 0x7Fu) << 1) | 0u);
}

/* Build address byte for read phase from a 7-bit slave address. */
static uint8_t i2c_priv_addr_rd(uint8_t slave_address)
{
    return (uint8_t)(((slave_address & 0x7Fu) << 1) | 1u);
}

/* Convert a data-byte index into the requested TX error code scheme. */
static uint8_t i2c_priv_data_nack_flag(uint16_t index)
{
    uint16_t code = (uint16_t)I2C_TX_ERR_DATA_NACK_BASE + index;

    if (code > 0xFFu) {
        return I2C_TX_ERR_DATA_NACK_SAT;
    }

    return (uint8_t)code;
}

/*
 * Send one write-phase byte on the bus and return:
 *   I2C_TX_OK
 *   nack_code
 *   I2C_TX_ERR_CMD
 */
static uint8_t i2c_priv_write_phase_byte(uint32_t base, uint8_t byte, uint8_t nack_code)
{
    uint8_t ack_info;

    if (!i2c_priv_wait_cmd_ready(base)) {
        return I2C_TX_ERR_CMD;
    }

    i2c_write_txdata(base, byte);

    if (i2c_cmd_wr(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_done(base)) {
        return I2C_TX_ERR_CMD;
    }

    ack_info = i2c_ack(base);

    /* bit1 = valid, bit0 = ack value */
    if ((ack_info & 0x2u) == 0u) {
        return I2C_TX_ERR_CMD;
    }

    /* ack bit = 0 means ACK, ack bit = 1 means NACK */
    if ((ack_info & 0x1u) != 0u) {
        return nack_code;
    }

    return I2C_TX_OK;
}

/*----------------------------------------------------------------------------
 * Public low-level command helpers
 *----------------------------------------------------------------------------*/

bool i2c_cmd_start(uint32_t base)
{
    return i2c_priv_issue_cmd(base, I2C_CMD_START, false);
}

bool i2c_cmd_wr(uint32_t base)
{
    return i2c_priv_issue_cmd(base, I2C_CMD_WR, false);
}

bool i2c_cmd_rd(uint32_t base, bool rd_last)
{
    return i2c_priv_issue_cmd(base, I2C_CMD_RD, rd_last);
}

bool i2c_cmd_stop(uint32_t base)
{
    return i2c_priv_issue_cmd(base, I2C_CMD_STOP, false);
}

bool i2c_cmd_restart(uint32_t base)
{
    return i2c_priv_issue_cmd(base, I2C_CMD_RESTART, false);
}

void i2c_set_divisor(uint32_t base, uint16_t freq_kHz, uint8_t core_MHz)
{
    uint32_t numerator;
    uint32_t denominator;
    uint32_t divisor32;

    if ((freq_kHz == 0u) || (core_MHz == 0u)) {
        i2c_write_divisor_raw(base, 1u);
        return;
    }

    numerator   = (uint32_t)core_MHz * 1000u;
    denominator = 4u * (uint32_t)freq_kHz;
    divisor32   = numerator / denominator;

    if (divisor32 == 0u) {
        divisor32 = 1u;
    } else if (divisor32 > 0xFFFFu) {
        divisor32 = 0xFFFFu;
    }

    i2c_write_divisor_raw(base, (uint16_t)divisor32);
}

/*----------------------------------------------------------------------------
 * Public higher-level helpers
 *----------------------------------------------------------------------------*/

void i2c_init(uint32_t base, uint16_t freq_kHz, uint8_t core_MHz)
{
    i2c_set_divisor(base, freq_kHz, core_MHz);
}

uint8_t i2c_tx_byte(uint32_t base, uint8_t slave_address, uint8_t data)
{
    uint8_t status;

    if (!i2c_priv_wait_cmd_ready(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (i2c_cmd_start(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return I2C_TX_ERR_CMD;
    }

    status = i2c_priv_write_phase_byte(base,
                                       i2c_priv_addr_wr(slave_address),
                                       I2C_TX_ERR_ADDR_NACK);
    if (status != I2C_TX_OK) {
        (void)i2c_cmd_stop(base);
        (void)i2c_priv_wait_cmd_cycle(base);
        return status;
    }

    status = i2c_priv_write_phase_byte(base,
                                       data,
                                       i2c_priv_data_nack_flag(0u));
    if (status != I2C_TX_OK) {
        (void)i2c_cmd_stop(base);
        (void)i2c_priv_wait_cmd_cycle(base);
        return status;
    }

    if (!i2c_priv_wait_cmd_ready(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (i2c_cmd_stop(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return I2C_TX_ERR_CMD;
    }

    return I2C_TX_OK;
}

uint8_t i2c_tx_pkg(uint32_t base, uint8_t slave_address, const char *msg)
{
    uint16_t index;
    uint8_t status;

    if (msg == NULL) {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_ready(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (i2c_cmd_start(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return I2C_TX_ERR_CMD;
    }

    status = i2c_priv_write_phase_byte(base,
                                       i2c_priv_addr_wr(slave_address),
                                       I2C_TX_ERR_ADDR_NACK);
    if (status != I2C_TX_OK) {
        (void)i2c_cmd_stop(base);
        (void)i2c_priv_wait_cmd_cycle(base);
        return status;
    }

    for (index = 0u; msg[index] != '\0'; index++) {
        status = i2c_priv_write_phase_byte(base,
                                           (uint8_t)msg[index],
                                           i2c_priv_data_nack_flag(index));
        if (status != I2C_TX_OK) {
            (void)i2c_cmd_stop(base);
            (void)i2c_priv_wait_cmd_cycle(base);
            return status;
        }
    }

    if (!i2c_priv_wait_cmd_ready(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (i2c_cmd_stop(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return I2C_TX_ERR_CMD;
    }

    return I2C_TX_OK;
}

uint8_t i2c_tx_buf(uint32_t base, uint8_t slave_address, const uint8_t *data, uint8_t length)
{
    uint16_t index;
    uint8_t status;

    if ((data == NULL) && (length != 0u)) {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_ready(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (i2c_cmd_start(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return I2C_TX_ERR_CMD;
    }

    status = i2c_priv_write_phase_byte(base,
                                       i2c_priv_addr_wr(slave_address),
                                       I2C_TX_ERR_ADDR_NACK);
    if (status != I2C_TX_OK) {
        (void)i2c_cmd_stop(base);
        (void)i2c_priv_wait_cmd_cycle(base);
        return status;
    }

    for (index = 0u; index < (uint16_t)length; index++) {
        status = i2c_priv_write_phase_byte(base,
                                           data[index],
                                           i2c_priv_data_nack_flag(index));
        if (status != I2C_TX_OK) {
            (void)i2c_cmd_stop(base);
            (void)i2c_priv_wait_cmd_cycle(base);
            return status;
        }
    }

    if (!i2c_priv_wait_cmd_ready(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (i2c_cmd_stop(base)) {
        return I2C_TX_ERR_CMD;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return I2C_TX_ERR_CMD;
    }

    return I2C_TX_OK;
}

bool i2c_rx_pkg(uint32_t base, uint8_t slave_address, uint8_t *buffer, uint8_t length)
{
    uint16_t index;

    if ((buffer == NULL) && (length != 0u)) {
        return false;
    }

    if (length == 0u) {
        return true;
    }

    if (!i2c_priv_wait_cmd_ready(base)) {
        return false;
    }

    if (i2c_cmd_start(base)) {
        return false;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return false;
    }

    if (i2c_priv_write_phase_byte(base,
                                  i2c_priv_addr_rd(slave_address),
                                  I2C_TX_ERR_ADDR_NACK) != I2C_TX_OK) {
        (void)i2c_cmd_stop(base);
        (void)i2c_priv_wait_cmd_cycle(base);
        return false;
    }

    for (index = 0u; index < (uint16_t)length; index++) {
        bool rd_last = (index == ((uint16_t)length - 1u));

        if (!i2c_priv_wait_cmd_ready(base)) {
            (void)i2c_cmd_stop(base);
            (void)i2c_priv_wait_cmd_cycle(base);
            return false;
        }

        if (i2c_cmd_rd(base, rd_last)) {
            (void)i2c_cmd_stop(base);
            (void)i2c_priv_wait_cmd_cycle(base);
            return false;
        }

        if (!i2c_priv_wait_rd_valid(base)) {
            (void)i2c_cmd_stop(base);
            (void)i2c_priv_wait_cmd_cycle(base);
            return false;
        }

        buffer[index] = i2c_read_rxdata(base);
    }

    if (!i2c_priv_wait_cmd_ready(base)) {
        return false;
    }

    if (i2c_cmd_stop(base)) {
        return false;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return false;
    }

    return true;
}

bool i2c_rx_byte(uint32_t base, uint8_t slave_address, uint8_t *data)
{
    if (data == NULL) {
        return false;
    }

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
    uint16_t index;

    if ((tx_data == NULL) && (tx_len != 0u)) {
        return false;
    }

    if ((rx_data == NULL) && (rx_len != 0u)) {
        return false;
    }

    if ((tx_len == 0u) && (rx_len == 0u)) {
        return true;
    }

    if (!i2c_priv_wait_cmd_ready(base)) {
        return false;
    }

    if (i2c_cmd_start(base)) {
        return false;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return false;
    }

    /*
     * Write phase:
     * Send address+W only if there is transmit data.
     */
    if (tx_len != 0u) {
        if (i2c_priv_write_phase_byte(base,
                                      i2c_priv_addr_wr(slave_address),
                                      I2C_TX_ERR_ADDR_NACK) != I2C_TX_OK) {
            (void)i2c_cmd_stop(base);
            (void)i2c_priv_wait_cmd_cycle(base);
            return false;
        }

        for (index = 0u; index < (uint16_t)tx_len; index++) {
            if (i2c_priv_write_phase_byte(base,
                                          tx_data[index],
                                          i2c_priv_data_nack_flag(index)) != I2C_TX_OK) {
                (void)i2c_cmd_stop(base);
                (void)i2c_priv_wait_cmd_cycle(base);
                return false;
            }
        }
    }

    /*
     * Read phase:
     * If both TX and RX exist, insert RESTART between phases.
     * If RX only, address+R is sent immediately after START.
     */
    if (rx_len != 0u) {
        if (tx_len != 0u) {
            if (!i2c_priv_wait_cmd_ready(base)) {
                (void)i2c_cmd_stop(base);
                (void)i2c_priv_wait_cmd_cycle(base);
                return false;
            }

            if (i2c_cmd_restart(base)) {
                (void)i2c_cmd_stop(base);
                (void)i2c_priv_wait_cmd_cycle(base);
                return false;
            }

            if (!i2c_priv_wait_cmd_cycle(base)) {
                (void)i2c_cmd_stop(base);
                (void)i2c_priv_wait_cmd_cycle(base);
                return false;
            }
        }

        if (i2c_priv_write_phase_byte(base,
                                      i2c_priv_addr_rd(slave_address),
                                      I2C_TX_ERR_ADDR_NACK) != I2C_TX_OK) {
            (void)i2c_cmd_stop(base);
            (void)i2c_priv_wait_cmd_cycle(base);
            return false;
        }

        for (index = 0u; index < (uint16_t)rx_len; index++) {
            bool rd_last = (index == ((uint16_t)rx_len - 1u));

            if (!i2c_priv_wait_cmd_ready(base)) {
                (void)i2c_cmd_stop(base);
                (void)i2c_priv_wait_cmd_cycle(base);
                return false;
            }

            if (i2c_cmd_rd(base, rd_last)) {
                (void)i2c_cmd_stop(base);
                (void)i2c_priv_wait_cmd_cycle(base);
                return false;
            }

            if (!i2c_priv_wait_rd_valid(base)) {
                (void)i2c_cmd_stop(base);
                (void)i2c_priv_wait_cmd_cycle(base);
                return false;
            }

            rx_data[index] = i2c_read_rxdata(base);
        }
    }

    if (!i2c_priv_wait_cmd_ready(base)) {
        return false;
    }

    if (i2c_cmd_stop(base)) {
        return false;
    }

    if (!i2c_priv_wait_cmd_cycle(base)) {
        return false;
    }

    return true;
}