#include "spi_regs.h"

/*
 * spi_regs.c
 *
 * This is a simple polling-mode SPI driver that matches the behavior of the
 * current spi_regs.sv wrapper.
 *
 * Important RTL facts this driver is built around:
 *
 * 1) CTRL.START is a write-one pulse, not a latched run bit.
 * 2) STATUS.RX_VALID and STATUS.DONE are sticky until software clears them.
 * 3) CTRL.XFER_END qualifies the NEXT launched byte:
 *      0 = keep transaction open after that byte
 *      1 = close transaction after that byte completes
 * 4) A "transaction" only really starts when a byte is launched.
 *    Merely writing CTRL does not assert CS by itself unless a byte launch occurs.
 *
 * Practical usage model:
 *
 * - For a one-byte transfer:
 *      rx = spi_transfer_byte_blocking(tx, true);
 *
 * - For a multi-byte transaction:
 *      spi_write_byte(cmd0, false);
 *      spi_wait_not_busy();
 *      spi_wait_rx_valid();
 *      (void)spi_read_rxdata();
 *
 *      spi_write_byte(cmd1, false);
 *      ...
 *
 *      spi_write_byte(last, true);   // final byte closes the transaction
 *      spi_wait_not_busy();
 *      spi_wait_rx_valid();
 *      rx = spi_read_rxdata();
 *
 * The "begin/end transaction" helpers below only prepare the XFER_END state for
 * the next byte. They DO NOT directly begin or end bus activity by themselves.
 */


/*----------------------------------------------------------------------------
 * Initialization
 *----------------------------------------------------------------------------
 *
 * What this does:
 * - Enables the SPI peripheral
 * - Sets XFER_END = 1 as the safe default for single-byte transfers
 * - Disables SPI interrupts in this simple polling driver
 * - Clears any stale sticky interrupt-pending bits
 * - Clears any stale sticky status flags (DONE / RX_VALID)
 *
 * Why:
 * The SPI wrapper exposes sticky completion flags. Starting from a known clean
 * state avoids false-ready behavior on the first transfer after reset or re-init.
 */
void spi_init(void)
{
    /* Safe idle default:
     * - peripheral enabled
     * - next launched byte defaults to "final byte"
     */
    SPI_REG_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_XFER_END;

    /* Clear sticky STATUS.DONE / STATUS.RX_VALID. */
    spi_clear_status_flags();

    /* This file uses polling, so leave IRQ generation disabled. */
    SPI_REG_IRQ_EN = 0u;

    /* Clear any pending IRQ status from an earlier run or reset sequence. */
    SPI_REG_IRQ_STATUS = SPI_IRQ_DONE | SPI_IRQ_RX_VALID;
}


/*----------------------------------------------------------------------------
 * Status wait helpers
 *----------------------------------------------------------------------------
 *
 * These are tiny polling loops used by the higher-level blocking functions.
 * They intentionally do nothing but wait for the requested hardware condition.
 */

void spi_wait_tx_ready(void)
{
    /*
     * Wait until the wrapped vendor core reports that it can accept a new byte.
     *
     * Note:
     * For this wrapper, waiting for TX_READY is often optional in simple code
     * because the wrapper can hold a START request internally until the core is
     * ready. Still, this helper is useful for debugging or for more explicit
     * software sequencing.
     */
    while (!spi_tx_ready()) {
    }
}

void spi_wait_not_busy(void)
{
    /*
     * Wait until the currently launched byte is fully complete.
     *
     * BUSY is byte-scoped:
     * - 1 while a byte is in flight
     * - 0 when that byte has completed
     *
     * Note:
     * BUSY going low does not necessarily mean CS is inactive.
     * If the byte was launched with XFER_END = 0, the transaction can still be
     * open between bytes.
     */
    while (spi_is_busy()) {
    }
}

void spi_wait_rx_valid(void)
{
    /*
     * Wait until RXDATA contains a newly completed received byte.
     *
     * Important:
     * RX_VALID is sticky in the RTL, so callers must clear old sticky state
     * before starting a fresh blocking transfer. That is why
     * spi_transfer_byte_blocking() clears status first.
     */
    while (!spi_rx_valid()) {
    }
}


/*----------------------------------------------------------------------------
 * Byte launch helpers
 *----------------------------------------------------------------------------
 *
 * These helpers prepare and launch one SPI byte.
 */

void spi_start_byte(bool final_byte)
{
    /*
     * Launch exactly one SPI byte.
     *
     * final_byte = false:
     *   keep the transaction open after this byte
     *
     * final_byte = true:
     *   mark this byte as the last byte in the transaction
     *
     * Why this works:
     * The RTL samples CTRL.XFER_END at byte-launch time, then START pulses the
     * launch. Because START is W1P, it is not stored; it only triggers the
     * current launch.
     */
    uint32_t ctrl = SPI_CTRL_ENABLE | (final_byte ? SPI_CTRL_XFER_END : 0u);
    ctrl |= SPI_CTRL_START;
    SPI_REG_CTRL = ctrl;
}

void spi_write_byte(uint8_t data, bool final_byte)
{
    /*
     * Simple non-pipelined write-and-launch helper.
     *
     * This version waits until the previous byte is no longer busy before
     * launching the next one. That makes it safer and easier to reason about
     * for a basic polling driver.
     *
     * If you later want an optimized multi-byte routine, you can stage TXDATA
     * while BUSY=1 and launch the next byte after BUSY clears. For now, we keep
     * the behavior conservative and easy to debug.
     */
    spi_wait_not_busy();
    spi_write_txdata(data);
    spi_start_byte(final_byte);
}


/*----------------------------------------------------------------------------
 * Blocking transfer helper
 *----------------------------------------------------------------------------
 *
 * This is the easiest "send one byte and get one byte back" API.
 */

uint8_t spi_transfer_byte_blocking(uint8_t tx_data, bool final_byte)
{
    /*
     * Clear stale sticky completion flags FIRST.
     *
     * Why:
     * STATUS.RX_VALID and STATUS.DONE are sticky in the RTL. If we do not clear
     * them here, spi_wait_rx_valid() could return immediately because of an old
     * transfer, and we might read stale RXDATA.
     */
    spi_clear_status_flags();

    /* Stage and launch the byte. */
    spi_write_byte(tx_data, final_byte);

    /*
     * Wait for byte completion.
     *
     * In this wrapper:
     * - BUSY drops when the launched byte completes
     * - RX_VALID becomes set when RXDATA contains the received byte
     */
    spi_wait_not_busy();
    spi_wait_rx_valid();

    /*
     * Return the received byte.
     *
     * We do not clear RX_VALID here because some callers may want to inspect the
     * status after the transfer. The next blocking transfer will clear stale
     * flags before starting.
     */
    return spi_read_rxdata();
}


/*----------------------------------------------------------------------------
 * XFER_END state helpers
 *----------------------------------------------------------------------------
 *
 * These do NOT directly toggle the bus or assert/deassert CS.
 * They only prepare how the NEXT launched byte will be qualified.
 *
 * Because of that, these helpers are optional. In many programs, simply passing
 * final_byte into spi_write_byte() / spi_transfer_byte_blocking() is clearer.
 */

void spi_begin_transaction(void)
{
    /*
     * Prepare the NEXT launched byte to be NON-final.
     *
     * Use this only if you want to set transaction state ahead of time.
     * It does not start the transaction by itself.
     *
     * After this, the next launched byte will keep CS asserted after completion.
     */
    SPI_REG_CTRL = SPI_CTRL_ENABLE;
}

void spi_end_transaction(void)
{
    /*
     * Prepare the NEXT launched byte to be FINAL.
     *
     * Important:
     * This must be called BEFORE launching the last byte, not after.
     *
     * Why:
     * The RTL captures XFER_END at launch time. Calling this after the last byte
     * has already launched is too late to affect that byte.
     */
    SPI_REG_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_XFER_END;
}