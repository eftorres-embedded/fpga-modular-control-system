#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

#define PWM_BASE_ADDR   0x00030000u

#define REG_CTRL        0x00u
#define REG_PERIOD      0x04u
#define REG_APPLY       0x08u
#define REG_CH_ENABLE   0x0Cu
#define REG_STATUS      0x10u
#define REG_CNT         0x14u
#define REG_POLARITY    0x18u
#define REG_MOTOR_CTRL  0x1Cu
#define REG_DUTY_BASE   0x20u

#define CTRL_GLOBAL_EN  (1u << 0)

#define PWM_CHANNELS    10u
#define PWM_PERIOD      10000u
#define FRAME_DELAY_US  8000u
#define WAVE_STEPS      200u

static inline void mmio_write32(uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(PWM_BASE_ADDR + offset) = value;
}

static inline uint32_t mmio_read32(uint32_t offset)
{
    return *(volatile uint32_t *)(PWM_BASE_ADDR + offset);
}

static inline void pwm_write_duty(uint32_t ch, uint32_t duty)
{
    mmio_write32(REG_DUTY_BASE + (4u * ch), duty);
}

static uint32_t triangle_duty(uint32_t phase, uint32_t period_cycles)
{
    uint32_t half = WAVE_STEPS / 2u;

    if (phase < half) {
        return (phase * period_cycles) / half;
    } else {
        return ((WAVE_STEPS - 1u - phase) * period_cycles) / half;
    }
}

int main(void)
{
    uint32_t i;
    uint32_t step = 0u;
    uint32_t ch_enable_mask = 0u;

    printf("\nPWM multichannel fade test start\n");
    printf("Base = 0x%08X\n", PWM_BASE_ADDR);

    for (i = 0; i < PWM_CHANNELS; i++) {
        ch_enable_mask |= (1u << i);
    }

    mmio_write32(REG_PERIOD, PWM_PERIOD);
    mmio_write32(REG_CH_ENABLE, ch_enable_mask);
    mmio_write32(REG_POLARITY, 0x00000000u);
    mmio_write32(REG_MOTOR_CTRL, 0x00000000u);
    mmio_write32(REG_CTRL, CTRL_GLOBAL_EN);
    mmio_write32(REG_APPLY, 1u);

    // No printf inside this loop.
    // This keeps the animation independent of JTAG UART presence.
    while (1) {
        for (i = 0; i < PWM_CHANNELS; i++) {
            uint32_t phase_offset = (i * WAVE_STEPS) / PWM_CHANNELS;
            uint32_t phase = (step + phase_offset) % WAVE_STEPS;
            uint32_t duty = triangle_duty(phase, PWM_PERIOD);

            pwm_write_duty(i, duty);
        }

        mmio_write32(REG_APPLY, 1u);

        step = (step + 1u) % WAVE_STEPS;
        usleep(FRAME_DELAY_US);
    }

    return 0;
}