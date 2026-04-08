#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

/*
 * ADXL345 bring-up / baseline test for custom Nios V SPI peripheral
 *
 * Important project note:
 * - Terasic DE10-Lite G-sensor demo uses 3-wire SPI (shared SDIO line)
 * - This custom design uses explicit 4-wire SPI:
 *     MOSI -> GSENSOR_SDI
 *     MISO <- GSENSOR_SDO
 * - To avoid ambiguity, this code explicitly writes DATA_FORMAT = 0x00
 *   on every loop so the ADXL345 is definitely in 4-wire mode.
 *
 * Test flow in this file:
 * 1. Force DATA_FORMAT = 0x00 (explicit 4-wire)
 * 2. Read back DATA_FORMAT
 * 3. Read DEVID (known-good smoke test baseline)
 * 4. Put device in measurement mode (POWER_CONTROL = 0x08)
 * 5. Read X/Y/Z low and high bytes individually
 * 6. Print combined signed 16-bit axis values
 */

#define SPI_BASE 0x00031000u   /* Change only if system.h says otherwise */

#define MMIO32(addr) (*(volatile uint32_t *)(uintptr_t)(addr))

/* Register map from spi_regs.sv */
#define SPI_CTRL       MMIO32(SPI_BASE + 0x00u)
#define SPI_STATUS     MMIO32(SPI_BASE + 0x04u)
#define SPI_TXDATA     MMIO32(SPI_BASE + 0x08u)
#define SPI_RXDATA     MMIO32(SPI_BASE + 0x0Cu)
#define SPI_IRQ_EN     MMIO32(SPI_BASE + 0x10u)
#define SPI_IRQ_STATUS MMIO32(SPI_BASE + 0x14u)

/* CTRL bits */
#define CTRL_ENABLE        (1u << 0)
#define CTRL_START         (1u << 1)
#define CTRL_XFER_END      (1u << 2)
#define CTRL_CLR_DONE      (1u << 3)
#define CTRL_CLR_RX_VALID  (1u << 4)

/* STATUS bits */
#define STATUS_BUSY        (1u << 0)
#define STATUS_DONE        (1u << 1)
#define STATUS_RX_VALID    (1u << 2)
#define STATUS_TX_READY    (1u << 3)
#define STATUS_ENABLED     (1u << 4)
#define STATUS_CS_ACTIVE   (1u << 5)
#define STATUS_XFER_OPEN   (1u << 6)

/* ADXL345 register addresses */
#define ADXL345_DEVID         0x00u
#define ADXL345_BW_RATE       0x2Cu
#define ADXL345_POWER_CTL     0x2Du
#define ADXL345_DATA_FORMAT   0x31u
#define ADXL345_DATAX0        0x32u
#define ADXL345_DATAX1        0x33u
#define ADXL345_DATAY0        0x34u
#define ADXL345_DATAY1        0x35u
#define ADXL345_DATAZ0        0x36u
#define ADXL345_DATAZ1        0x37u

int main(void)
{
    uint32_t status;
    uint8_t rx0;
    uint8_t rx1;

    uint8_t data_format_read;
    uint8_t devid;
    uint8_t power_ctl_read;

    uint8_t x_lb, x_hb;
    uint8_t y_lb, y_hb;
    uint8_t z_lb, z_hb;

    int16_t x_axis;
    int16_t y_axis;
    int16_t z_axis;

    printf("\n");
    printf("ADXL345 baseline + axis-read test\n");
    printf("SPI base = 0x%08X\n", SPI_BASE);
    printf("Mode policy: explicit 4-wire (DATA_FORMAT = 0x00)\n");

    /* no interrupts for this simple test */
    SPI_IRQ_EN = 0;

    /* enable peripheral */
    SPI_CTRL = CTRL_ENABLE;
    SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

    status = SPI_STATUS;
    printf("Initial STATUS = 0x%08X\n", status);

    while (1)
    {
        /****************************************************************/
        /* 1) WRITE DATA_FORMAT = 0x00  (explicit 4-wire mode)          */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        SPI_TXDATA = ADXL345_DATA_FORMAT;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));

        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));

        rx1 = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /****************************************************************/
        /* 2) READ BACK DATA_FORMAT                                     */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        SPI_TXDATA = 0x80u | ADXL345_DATA_FORMAT;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));

        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));

        data_format_read = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /****************************************************************/
        /* 3) READ DEVID  (known-good baseline smoke test)              */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        SPI_TXDATA = 0x80u | ADXL345_DEVID;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));

        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));

        devid = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        printf("DATA_FORMAT = 0x%02X", data_format_read);
        if (data_format_read == 0x00) {
            printf("  <-- 4-wire confirmed\n");
        } else {
            printf("  <-- unexpected\n");
        }

        printf("DEVID       = 0x%02X", devid);
        if (devid == 0xE5) {
            printf("  <-- PASS\n");
        } else {
            printf("  <-- FAIL\n");
            printf("Final STATUS = 0x%08X\n\n", status);
            usleep(500000);
            continue;
        }

        /****************************************************************/
        /* 4) WRITE POWER_CONTROL = 0x08  (measurement mode)            */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        SPI_TXDATA = ADXL345_POWER_CTL;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));

        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_TXDATA = 0x08u;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));

        rx1 = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /* small delay after entering measurement mode */
        usleep(10000);

        /****************************************************************/
        /* 5) READ BACK POWER_CONTROL                                   */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        SPI_TXDATA = 0x80u | ADXL345_POWER_CTL;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));

        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));

        power_ctl_read = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        printf("POWER_CTL   = 0x%02X\n", power_ctl_read);

        /****************************************************************/
        /* 6) READ X_LB                                                 */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;
        SPI_TXDATA = 0x80u | ADXL345_DATAX0;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));
        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));
        x_lb = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /****************************************************************/
        /* 7) READ X_HB                                                 */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;
        SPI_TXDATA = 0x80u | ADXL345_DATAX1;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));
        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));
        x_hb = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /****************************************************************/
        /* 8) READ Y_LB                                                 */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;
        SPI_TXDATA = 0x80u | ADXL345_DATAY0;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));
        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));
        y_lb = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /****************************************************************/
        /* 9) READ Y_HB                                                 */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;
        SPI_TXDATA = 0x80u | ADXL345_DATAY1;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));
        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));
        y_hb = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /****************************************************************/
        /* 10) READ Z_LB                                                */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;
        SPI_TXDATA = 0x80u | ADXL345_DATAZ0;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));
        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));
        z_lb = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /****************************************************************/
        /* 11) READ Z_HB                                                */
        /****************************************************************/
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;
        SPI_TXDATA = 0x80u | ADXL345_DATAZ1;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));
        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));
        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));
        z_hb = (uint8_t)(SPI_RXDATA & 0xFFu);
        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        x_axis = (int16_t)(((uint16_t)x_hb << 8) | x_lb);
        y_axis = (int16_t)(((uint16_t)y_hb << 8) | y_lb);
        z_axis = (int16_t)(((uint16_t)z_hb << 8) | z_lb);

        printf("X raw = 0x%02X%02X (%d)\n", x_hb, x_lb, x_axis);
        printf("Y raw = 0x%02X%02X (%d)\n", y_hb, y_lb, y_axis);
        printf("Z raw = 0x%02X%02X (%d)\n", z_hb, z_lb, z_axis);
        printf("Final STATUS = 0x%08X\n", status);
        printf("--------------------------------------------------\n");

        usleep(500000);
    }

    return 0;
}