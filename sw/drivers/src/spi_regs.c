#include "spi_regs.h"

void spi_init(void)
{
    SPI_REG_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_XFER_END;
    SPI_REG_IRQ_EN = 0u;
    SPI_REG_IRQ_STATUS = SPI_IRQ_DONE | SPI_IRQ_RX_VALID;
}

void spi_wait_tx_ready(void)
{
    while (!spi_tx_ready()) {
    }
}

void spi_wait_not_busy(void)
{
    while (spi_is_busy()) {
    }
}

void spi_wait_rx_valid(void)
{
    while (!spi_rx_valid()) {
    }
}

void spi_start_byte(bool final_byte)
{
    uint32_t ctrl = SPI_CTRL_ENABLE | (final_byte ? SPI_CTRL_XFER_END : 0u);
    ctrl |= SPI_CTRL_START;
    SPI_REG_CTRL = ctrl;
}

void spi_write_byte(uint8_t data, bool final_byte)
{
    spi_write_txdata(data);
    spi_start_byte(final_byte);
}

uint8_t spi_transfer_byte_blocking(uint8_t tx_data, bool final_byte)
{
    spi_write_byte(tx_data, final_byte);
    spi_wait_not_busy();
    spi_wait_rx_valid();
    return spi_read_rxdata();
}

void spi_begin_transaction(void)
{
    SPI_REG_CTRL = SPI_CTRL_ENABLE;
}

void spi_end_transaction(void)
{
    SPI_REG_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_XFER_END;
}