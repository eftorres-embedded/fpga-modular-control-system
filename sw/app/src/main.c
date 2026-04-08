#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

#define SPI_BASE 0x00031000u   /* Change only if your system.h says otherwise */

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

int main(void)
{
    uint32_t status;
    uint8_t rx0;
    uint8_t rx1;

    uint8_t data_format_read;
    uint8_t devid;

    printf("\n");
    printf("SPI ADXL345 explicit 4-wire test\n");
    printf("SPI base = 0x%08X\n", SPI_BASE);

    /* no interrupts for this simple test */
    SPI_IRQ_EN = 0;

    /* enable peripheral */
    SPI_CTRL = CTRL_ENABLE;

    /* clear sticky flags */
    SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

    status = SPI_STATUS;
    printf("Initial STATUS = 0x%08X\n", status);

    while (1)
    {
        /********************************************************************/
        /* STEP 1: WRITE DATA_FORMAT = 0x00                                 */
        /* This explicitly selects 4-wire SPI mode on ADXL345               */
        /* write register 0x31 with value 0x00                              */
        /********************************************************************/

        /* wait until idle and ready */
        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /* byte 0 = write command/address 0x31 */
        SPI_TXDATA = 0x31;
        SPI_CTRL = CTRL_ENABLE;              /* next launched byte is not final */
        SPI_CTRL = CTRL_ENABLE | CTRL_START; /* launch byte 0 */

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));

        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu); /* throwaway for write phase */

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        /* byte 1 = data 0x00, final byte */
        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));

        rx1 = (uint8_t)(SPI_RXDATA & 0xFFu); /* throwaway for write phase */

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        printf("WRITE DATA_FORMAT=0x00 done, STATUS=0x%08X RX0=0x%02X RX1=0x%02X\n",
               status, rx0, rx1);

        /********************************************************************/
        /* STEP 2: READ BACK DATA_FORMAT                                    */
        /* read register 0x31                                                */
        /* command byte = 0x80 | 0x31 = 0xB1                                */
        /********************************************************************/

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /* byte 0 = read command/address 0xB1 */
        SPI_TXDATA = 0xB1;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));

        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu); /* usually not the register data */

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        /* byte 1 = dummy 0x00, final byte */
        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));

        data_format_read = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        printf("READ  DATA_FORMAT = 0x%02X", data_format_read);
        if (data_format_read == 0x00) {
            printf("  <-- 4-wire confirmed\n");
        } else {
            printf("  <-- unexpected\n");
        }

        /********************************************************************/
        /* STEP 3: READ DEVID                                                */
        /* read register 0x00                                                */
        /* command byte = 0x80                                               */
        /********************************************************************/

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        /* byte 0 = read command/address 0x80 */
        SPI_TXDATA = 0x80;
        SPI_CTRL = CTRL_ENABLE;
        SPI_CTRL = CTRL_ENABLE | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_RX_VALID));

        rx0 = (uint8_t)(SPI_RXDATA & 0xFFu); /* usually not the final data */

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_RX_VALID;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_TX_READY));

        /* byte 1 = dummy 0x00, final byte */
        SPI_TXDATA = 0x00;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END;
        SPI_CTRL = CTRL_ENABLE | CTRL_XFER_END | CTRL_START;

        do {
            status = SPI_STATUS;
        } while ((status & STATUS_BUSY) || !(status & STATUS_DONE) || !(status & STATUS_RX_VALID));

        devid = (uint8_t)(SPI_RXDATA & 0xFFu);

        SPI_CTRL = CTRL_ENABLE | CTRL_CLR_DONE | CTRL_CLR_RX_VALID;

        printf("READ  DEVID       = 0x%02X", devid);
        if (devid == 0xE5) {
            printf("  <-- PASS\n");
        } else {
            printf("  <-- FAIL\n");
        }

        printf("Final STATUS      = 0x%08X\n", status);
        printf("\n");

        usleep(500000);
    }

    return 0;
}