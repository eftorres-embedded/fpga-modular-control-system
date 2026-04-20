#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

#include "spi_regs.h"
#include "adxl345.h"

/*
 * Small ADXL345 bring-up test for the current polling-mode SPI stack.
 *
 * What this test does:
 * 1) Initializes the SPI peripheral
 * 2) Runs the conservative ADXL345 bring-up sequence
 * 3) Reads back DATA_FORMAT, DEVID, BW_RATE, and POWER_CTL
 * 4) Continuously prints raw X/Y/Z samples
 *
 * Expected baseline after adxl345_init_default():
 *   DATA_FORMAT = 0x00  (4-wire SPI, +/-2 g, right-justified, no self-test)
 *   DEVID       = 0xE5
 *   BW_RATE     = 0x0A  (100 Hz)
 *   POWER_CTL   = 0x08  (MEASURE = 1)
 */

static void print_reg_u8(const char *name, uint8_t reg)
{
    uint8_t value = 0u;
    adxl345_status_t st = adxl345_read_reg(reg, &value);

    if (st == ADXL345_OK) {
        printf("%s = 0x%02X\n", name, value);
    } else {
        printf("%s read failed, status = %d\n", name, (int)st);
    }
}

int main(void)
{
    adxl345_status_t st;
    adxl345_raw_xyz_t xyz;
    uint8_t devid = 0u;

    printf("\nADXL345 SPI bring-up test\n");
    printf("Initializing SPI...\n");
    spi_init();

    printf("Running ADXL345 default init...\n");
    st = adxl345_init_default();
    if (st != ADXL345_OK) {
        printf("ADXL345 init failed, status = %d\n", (int)st);
        while (1) {
            usleep(250000);
        }
    }

    st = adxl345_read_device_id(&devid);
    if (st != ADXL345_OK) {
        printf("DEVID read failed, status = %d\n", (int)st);
        while (1) {
            usleep(250000);
        }
    }

    printf("\nInitial register readback:\n");
    print_reg_u8("DATA_FORMAT", ADXL345_REG_DATA_FORMAT);
    print_reg_u8("DEVID",       ADXL345_REG_DEVID);
    print_reg_u8("BW_RATE",     ADXL345_REG_BW_RATE);
    print_reg_u8("POWER_CTL",   ADXL345_REG_POWER_CTL);

    if (devid != ADXL345_DEVID_VALUE) {
        printf("Unexpected DEVID: got 0x%02X, expected 0x%02X\n",
               devid, ADXL345_DEVID_VALUE);
        while (1) {
            usleep(250000);
        }
    }

    printf("\nStreaming raw X/Y/Z values...\n");
    printf("(Ctrl+C / stop from debugger when done)\n\n");

    while (1) {
        st = adxl345_read_xyz_raw(&xyz);
        if (st != ADXL345_OK) {
            printf("XYZ read failed, status = %d\n", (int)st);
        } else {
            printf("X=%6d  Y=%6d  Z=%6d\n",
                   (int)xyz.x,
                   (int)xyz.y,
                   (int)xyz.z);
        }

        /* 10 Hz print rate is easy to read in the JTAG UART console. */
        usleep(100000);
    }

    return 0;
}
