#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

/*
 * Minimal Avalon I2C Host idle/reset debug test
 *
 * Purpose:
 *   Isolate whether the I2C core is already non-idle / driving the bus
 *   before any transfer command is ever queued.
 *
 * What this test does:
 *   1) Prints the raw CSR state immediately after boot.
 *   2) Forces CTRL = 0 (core disabled), then prints state again.
 *   3) Programs timing registers while still disabled, then prints state.
 *   4) Enables the core (CTRL.EN = 1), prints state immediately, then again
 *      after short delays.
 *   5) Disables the core again and prints the final state.
 *
 * What this test does NOT do:
 *   - It does NOT write TFR_CMD.
 *   - It does NOT try to talk to the MPU-6500.
 *
 * Expected use:
 *   Run this together with Signal Tap on:
 *     mpu_i2c_scl_drive_low
 *     mpu_i2c_scl_i
 *     mpu_i2c_sda_drive_low
 *     mpu_i2c_sda_i
 *
 * Assumptions:
 *   - Avalon I2C Host base address = 0x00033000
 *   - Avalon I2C Host is configured for Avalon-MM FIFO access
 *   - I2C host clock = 50 MHz
 */

#define I2C_BASE_ADDR           0x00033000u

/* Avalon I2C register word offsets */
#define REG_TFR_CMD             0x0u
#define REG_RX_DATA             0x1u
#define REG_CTRL                0x2u
#define REG_ISER                0x3u
#define REG_ISR                 0x4u
#define REG_STATUS              0x5u
#define REG_TFR_CMD_FIFO_LVL    0x6u
#define REG_RX_DATA_FIFO_LVL    0x7u
#define REG_SCL_LOW             0x8u
#define REG_SCL_HIGH            0x9u
#define REG_SDA_HOLD            0xAu

/* CTRL bits */
#define CTRL_EN                 (1u << 0)
#define CTRL_BUS_SPEED_FAST     (1u << 1)

/* ISR bits */
#define ISR_TX_READY            (1u << 0)
#define ISR_RX_READY            (1u << 1)
#define ISR_NACK_DET            (1u << 2)
#define ISR_ARBLOST_DET         (1u << 3)
#define ISR_RX_OVER             (1u << 4)
#define ISR_ALL_W1C_ERRORS      (ISR_NACK_DET | ISR_ARBLOST_DET | ISR_RX_OVER)

/* STATUS bits */
#define STATUS_CORE_BUSY        (1u << 0)

static inline uintptr_t reg_addr(uint32_t word_off)
{
    return (uintptr_t)(I2C_BASE_ADDR + (word_off << 2));
}

static inline void mmio_write(uint32_t word_off, uint32_t value)
{
    *(volatile uint32_t *)reg_addr(word_off) = value;
}

static inline uint32_t mmio_read(uint32_t word_off)
{
    return *(volatile uint32_t *)reg_addr(word_off);
}

static void clear_i2c_errors(void)
{
    mmio_write(REG_ISR, ISR_ALL_W1C_ERRORS);
}

static void drain_rx_fifo(void)
{
    while (mmio_read(REG_RX_DATA_FIFO_LVL) != 0u) {
        (void)mmio_read(REG_RX_DATA);
    }
}

static void dump_i2c_state(const char *tag)
{
    uint32_t ctrl   = mmio_read(REG_CTRL);
    uint32_t iser   = mmio_read(REG_ISER);
    uint32_t isr    = mmio_read(REG_ISR);
    uint32_t status = mmio_read(REG_STATUS);
    uint32_t tfrlvl = mmio_read(REG_TFR_CMD_FIFO_LVL);
    uint32_t rxlvl  = mmio_read(REG_RX_DATA_FIFO_LVL);
    uint32_t scll   = mmio_read(REG_SCL_LOW);
    uint32_t sclh   = mmio_read(REG_SCL_HIGH);
    uint32_t sdah   = mmio_read(REG_SDA_HOLD);

    printf("\n[%s]\n", tag);
    printf("CTRL     = 0x%08X  (EN=%u, BUS_SPEED_FAST=%u)\n",
           ctrl, (ctrl >> 0) & 1u, (ctrl >> 1) & 1u);
    printf("ISER     = 0x%08X\n", iser);
    printf("ISR      = 0x%08X  (TX_READY=%u RX_READY=%u NACK=%u ARBLOST=%u RX_OVER=%u)\n",
           isr,
           (isr >> 0) & 1u,
           (isr >> 1) & 1u,
           (isr >> 2) & 1u,
           (isr >> 3) & 1u,
           (isr >> 4) & 1u);
    printf("STATUS   = 0x%08X  (CORE_BUSY=%u)\n",
           status, (status >> 0) & 1u);
    printf("TFR_LVL  = %u\n", tfrlvl);
    printf("RX_LVL   = %u\n", rxlvl);
    printf("SCL_LOW  = %u\n", scll);
    printf("SCL_HIGH = %u\n", sclh);
    printf("SDA_HOLD = %u\n", sdah);
}

int main(void)
{
    printf("\n=== Avalon I2C idle/reset debug test ===\n");
    printf("I2C CSR base = 0x%08X\n", I2C_BASE_ADDR);
    printf("This test does NOT write TFR_CMD.\n");
    printf("It only disables/enables the core and prints raw register state.\n");

    dump_i2c_state("power-up raw state");

    /* Put the core in the quietest possible state first */
    mmio_write(REG_CTRL, 0u);
    mmio_write(REG_ISER, 0u);
    clear_i2c_errors();
    drain_rx_fifo();

    dump_i2c_state("after forcing CTRL=0 and clearing ISR/RX");

    usleep(20000);
    dump_i2c_state("20 ms later with CTRL=0");

    /*
     * Program timing while still disabled.
     * 50 MHz -> 100 kHz bus target:
     *   250 low + 250 high = 500 clocks total.
     */
    mmio_write(REG_SCL_LOW,  250u);
    mmio_write(REG_SCL_HIGH, 250u);
    mmio_write(REG_SDA_HOLD, 25u);

    dump_i2c_state("after timing writes, still CTRL=0");

    /* Enable core, but still do not queue any transfer command */
    mmio_write(REG_CTRL, CTRL_EN);
    dump_i2c_state("immediately after CTRL.EN=1");

    usleep(1000);
    dump_i2c_state("1 ms after CTRL.EN=1");

    usleep(10000);
    dump_i2c_state("10 ms after CTRL.EN=1");

    usleep(100000);
    dump_i2c_state("100 ms after CTRL.EN=1");

    /* Disable again */
    mmio_write(REG_CTRL, 0u);
    usleep(1000);
    dump_i2c_state("1 ms after CTRL.EN=0 again");

    printf("\nInterpretation guide:\n");
    printf(" - If CORE_BUSY=1 even when CTRL=0 and no TFR_CMD was written,\n");
    printf("   suspect reset/integration/stale-image issues.\n");
    printf(" - If CORE_BUSY changes only when CTRL.EN changes, the enable path matters.\n");
    printf(" - With Signal Tap, also watch whether scl/sda drive_low changes at those moments.\n");

    return 0;
}
