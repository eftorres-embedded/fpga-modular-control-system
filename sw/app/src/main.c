#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

#include "user_define_system.h"
#include "mmio.h"

#define I2C_REG_STATUS_OFFSET   0x00u
#define I2C_REG_DIVISOR_OFFSET  0x04u
#define I2C_REG_TXDATA_OFFSET   0x08u
#define I2C_REG_RXDATA_OFFSET   0x0Cu
#define I2C_REG_CMD_OFFSET      0x10u

int main(void)
{
    uint32_t status;
    uint32_t divisor;
    uint32_t txdata;
    uint32_t rxdata;
    uint32_t my_reg;

    printf("entered main\n");
    fflush(stdout);

    status  = mmio_read32(I2C_BASE, I2C_REG_STATUS_OFFSET);
    printf("I2C status  = 0x%08lX\n", (unsigned long)status);
    divisor = mmio_read32(I2C_BASE, I2C_REG_DIVISOR_OFFSET);
    printf("I2C divisor = 0x%08lX\n", (unsigned long)divisor);
    txdata  = mmio_read32(I2C_BASE, I2C_REG_TXDATA_OFFSET);
    printf("I2C txdata  = 0x%08lX\n", (unsigned long)txdata);
    rxdata  = mmio_read32(I2C_BASE, I2C_REG_RXDATA_OFFSET);
    printf("I2C rxdata  = 0x%08lX\n", (unsigned long)rxdata);
    //my_reg     = mmio_read32(I2C_BASE, 0x014);   /* this one may error/hang if REG_CMD is write-only through your fabric */
    //printf("I2C debug reg  = 0x%08lX\n", (unsigned long)my_reg);
    //printf("I2C debug   = 0x%08lX\n", (unsigned long)mmio_read32(I2C_BASE, 0x014u));
    fflush(stdout);
    printf("This is the end \n");



    while (1) {
        usleep(500000);
    }

    return 0;
}