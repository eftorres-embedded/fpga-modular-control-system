#ifndef SPI_REGS_H
#define SPI_REGS_H

#include <stdint.h>
#include <stdbool.h>

/* -------------------------------------------------------------------------
 * SPI peripheral base address
 * ------------------------------------------------------------------------- */
#define SPI_BASE_ADDR           0x00031000u

/* -------------------------------------------------------------------------
 * SPI interrupt number
 * ------------------------------------------------------------------------- */
#define SPI_IRQ_NUM             1u

/* -------------------------------------------------------------------------
 * Register offsets
 * ------------------------------------------------------------------------- */
#define SPI_REG_CTRL_OFFSET         0x00u
#define SPI_REG_STATUS_OFFSET       0x04u
#define SPI_REG_TXDATA_OFFSET       0x08u
#define SPI_REG_RXDATA_OFFSET       0x0Cu
#define SPI_REG_IRQ_EN_OFFSET       0x10u
#define SPI_REG_IRQ_STATUS_OFFSET   0x14u

/* -------------------------------------------------------------------------
 * Absolute register addresses
 * ------------------------------------------------------------------------- */
#define SPI_REG_CTRL_ADDR         (SPI_BASE_ADDR + SPI_REG_CTRL_OFFSET)
#define SPI_REG_STATUS_ADDR       (SPI_BASE_ADDR + SPI_REG_STATUS_OFFSET)
#define SPI_REG_TXDATA_ADDR       (SPI_BASE_ADDR + SPI_REG_TXDATA_OFFSET)
#define SPI_REG_RXDATA_ADDR       (SPI_BASE_ADDR + SPI_REG_RXDATA_OFFSET)
#define SPI_REG_IRQ_EN_ADDR       (SPI_BASE_ADDR + SPI_REG_IRQ_EN_OFFSET)
#define SPI_REG_IRQ_STATUS_ADDR   (SPI_BASE_ADDR + SPI_REG_IRQ_STATUS_OFFSET)

/* -------------------------------------------------------------------------
 * Register access macros
 * ------------------------------------------------------------------------- */
#define SPI_REG_CTRL         (*(volatile uint32_t *)(SPI_REG_CTRL_ADDR))
#define SPI_REG_STATUS       (*(volatile uint32_t *)(SPI_REG_STATUS_ADDR))
#define SPI_REG_TXDATA       (*(volatile uint32_t *)(SPI_REG_TXDATA_ADDR))
#define SPI_REG_RXDATA       (*(volatile uint32_t *)(SPI_REG_RXDATA_ADDR))
#define SPI_REG_IRQ_EN       (*(volatile uint32_t *)(SPI_REG_IRQ_EN_ADDR))
#define SPI_REG_IRQ_STATUS   (*(volatile uint32_t *)(SPI_REG_IRQ_STATUS_ADDR))

/* -------------------------------------------------------------------------
 * CTRL register bits
 * ------------------------------------------------------------------------- */
#define SPI_CTRL_ENABLE_BIT         0u
#define SPI_CTRL_START_BIT          1u
#define SPI_CTRL_XFER_END_BIT       2u
#define SPI_CTRL_CLR_DONE_BIT       3u
#define SPI_CTRL_CLR_RX_VALID_BIT   4u

#define SPI_CTRL_ENABLE         (1u << SPI_CTRL_ENABLE_BIT)
#define SPI_CTRL_START          (1u << SPI_CTRL_START_BIT)
#define SPI_CTRL_XFER_END       (1u << SPI_CTRL_XFER_END_BIT)
#define SPI_CTRL_CLR_DONE       (1u << SPI_CTRL_CLR_DONE_BIT)
#define SPI_CTRL_CLR_RX_VALID   (1u << SPI_CTRL_CLR_RX_VALID_BIT)

/* -------------------------------------------------------------------------
 * STATUS register bits
 * ------------------------------------------------------------------------- */
#define SPI_STATUS_BUSY_BIT         0u
#define SPI_STATUS_DONE_BIT         1u
#define SPI_STATUS_RX_VALID_BIT     2u
#define SPI_STATUS_TX_READY_BIT     3u
#define SPI_STATUS_ENABLED_BIT      4u
#define SPI_STATUS_CS_ACTIVE_BIT    5u
#define SPI_STATUS_XFER_OPEN_BIT    6u

#define SPI_STATUS_BUSY         (1u << SPI_STATUS_BUSY_BIT)
#define SPI_STATUS_DONE         (1u << SPI_STATUS_DONE_BIT)
#define SPI_STATUS_RX_VALID     (1u << SPI_STATUS_RX_VALID_BIT)
#define SPI_STATUS_TX_READY     (1u << SPI_STATUS_TX_READY_BIT)
#define SPI_STATUS_ENABLED      (1u << SPI_STATUS_ENABLED_BIT)
#define SPI_STATUS_CS_ACTIVE    (1u << SPI_STATUS_CS_ACTIVE_BIT)
#define SPI_STATUS_XFER_OPEN    (1u << SPI_STATUS_XFER_OPEN_BIT)

/* -------------------------------------------------------------------------
 * IRQ_EN / IRQ_STATUS bits
 * ------------------------------------------------------------------------- */
#define SPI_IRQ_DONE_BIT            0u
#define SPI_IRQ_RX_VALID_BIT        1u

#define SPI_IRQ_DONE            (1u << SPI_IRQ_DONE_BIT)
#define SPI_IRQ_RX_VALID        (1u << SPI_IRQ_RX_VALID_BIT)

/* -------------------------------------------------------------------------
 * Low-level MMIO helpers
 * ------------------------------------------------------------------------- */
static inline void spi_enable(void)
{
    SPI_REG_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_XFER_END;
}

static inline void spi_disable(void)
{
    SPI_REG_CTRL = SPI_CTRL_XFER_END;
}

static inline uint32_t spi_status_read(void)
{
    return SPI_REG_STATUS;
}

static inline bool spi_is_busy(void)
{
    return (SPI_REG_STATUS & SPI_STATUS_BUSY) != 0u;
}

static inline bool spi_tx_ready(void)
{
    return (SPI_REG_STATUS & SPI_STATUS_TX_READY) != 0u;
}

static inline bool spi_rx_valid(void)
{
    return (SPI_REG_STATUS & SPI_STATUS_RX_VALID) != 0u;
}

static inline bool spi_xfer_open(void)
{
    return (SPI_REG_STATUS & SPI_STATUS_XFER_OPEN) != 0u;
}

static inline void spi_write_txdata(uint8_t data)
{
    SPI_REG_TXDATA = (uint32_t)data;
}

static inline uint8_t spi_read_rxdata(void)
{
    return (uint8_t)(SPI_REG_RXDATA & 0xFFu);
}

static inline void spi_clear_done(void)
{
    SPI_REG_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_XFER_END | SPI_CTRL_CLR_DONE;
}

static inline void spi_clear_rx_valid(void)
{
    SPI_REG_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_XFER_END | SPI_CTRL_CLR_RX_VALID;
}

static inline void spi_clear_status_flags(void)
{
    SPI_REG_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_XFER_END |
                   SPI_CTRL_CLR_DONE | SPI_CTRL_CLR_RX_VALID;
}

static inline void spi_irq_enable(uint32_t mask)
{
    SPI_REG_IRQ_EN = mask;
}

static inline uint32_t spi_irq_status_read(void)
{
    return SPI_REG_IRQ_STATUS;
}

static inline void spi_irq_clear(uint32_t mask)
{
    SPI_REG_IRQ_STATUS = mask;
}

/* -------------------------------------------------------------------------
 * Common driver API declarations
 * Implement these in spi_regs.c or spi_master.c
 * ------------------------------------------------------------------------- */
void spi_init(void);
void spi_start_byte(bool final_byte);
void spi_write_byte(uint8_t data, bool final_byte);
uint8_t spi_transfer_byte_blocking(uint8_t tx_data, bool final_byte);

void spi_wait_tx_ready(void);
void spi_wait_not_busy(void);
void spi_wait_rx_valid(void);

void spi_begin_transaction(void);
void spi_end_transaction(void);

void spi_irq_handler(void);

#endif /* SPI_REGS_H */