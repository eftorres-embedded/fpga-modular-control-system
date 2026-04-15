#include <stdio.h>
#include <stdint.h>
#include <unistd.h>

// -----------------------------------------------------------------------------
// Platform Designer base addresses
// -----------------------------------------------------------------------------
#define MOTOR_PWM_BASE   0x00030000u
#define LED_PWM_BASE     0x00032000u

// -----------------------------------------------------------------------------
// Common PWM-family register map
// -----------------------------------------------------------------------------
#define REG_CTRL         0x00u
#define REG_PERIOD       0x04u
#define REG_APPLY        0x08u
#define REG_CH_ENABLE    0x0Cu
#define REG_STATUS       0x10u
#define REG_CNT          0x14u
#define REG_DUTY_BASE    0x20u

// -----------------------------------------------------------------------------
// Motor flavor extension registers
// -----------------------------------------------------------------------------
#define REG_DIR_MASK     0x40u
#define REG_BRAKE_MASK   0x44u
#define REG_COAST_MASK   0x48u

#define CTRL_GLOBAL_EN   (1u << 0)

// -----------------------------------------------------------------------------
// LED raw-PWM config
// -----------------------------------------------------------------------------
#define LED_PWM_CHANNELS    10u
#define LED_PWM_PERIOD      10000u
#define FRAME_DELAY_US      8000u

// 32-sample sine-like lookup, normalized to 0..1000
#define LED_WAVE_STEPS      32u
static const uint16_t led_wave_table[LED_WAVE_STEPS] = {
    500, 598, 691, 778, 854, 916, 962, 990,
    1000, 990, 962, 916, 854, 778, 691, 598,
    500, 402, 309, 222, 146, 84, 38, 10,
    0, 10, 38, 84, 146, 222, 309, 402
};

// -----------------------------------------------------------------------------
// Motor PWM config
// 50 MHz / 2500 = 20 kHz PWM
// Timing based on FRAME_DELAY_US = 8000 us
//   5.0 s  / 0.008 s = 625 frames
//   2.0 s  / 0.008 s = 250 frames
//   0.5 s  / 0.008 s = 62.5 -> 63 frames
// -----------------------------------------------------------------------------
#define MOTOR_PWM_PERIOD     2500u
#define MOTOR_MAX_DUTY       ((MOTOR_PWM_PERIOD * 80u) / 100u)  // 80%

#define MOTOR_RAMP_FRAMES    625u
#define MOTOR_HOLD_FRAMES    250u
#define MOTOR_BRAKE_FRAMES   63u

// Based on your top-level concatenation:
//   {motor_a_*, motor_b_*} -> bit1 = motor A, bit0 = motor B
#define MOTOR_CH_B           0u
#define MOTOR_CH_A           1u

#define MOTOR_MASK_A         (1u << MOTOR_CH_A)
#define MOTOR_MASK_B         (1u << MOTOR_CH_B)
#define MOTOR_MASK_BOTH      (MOTOR_MASK_A | MOTOR_MASK_B)

// -----------------------------------------------------------------------------
// MMIO helpers
// -----------------------------------------------------------------------------
static inline void mmio_write32(uint32_t base, uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(base + offset) = value;
}

static inline uint32_t mmio_read32(uint32_t base, uint32_t offset)
{
    return *(volatile uint32_t *)(base + offset);
}

static inline void pwm_write_duty(uint32_t base, uint32_t ch, uint32_t duty)
{
    mmio_write32(base, REG_DUTY_BASE + (4u * ch), duty);
}

static inline void pwm_apply(uint32_t base)
{
    mmio_write32(base, REG_APPLY, 1u);
}

// -----------------------------------------------------------------------------
// Common init
// -----------------------------------------------------------------------------
static void pwm_common_init(uint32_t base, uint32_t period, uint32_t ch_enable_mask)
{
    mmio_write32(base, REG_PERIOD, period);
    mmio_write32(base, REG_CH_ENABLE, ch_enable_mask);
    mmio_write32(base, REG_CTRL, CTRL_GLOBAL_EN);
    pwm_apply(base);
}

// -----------------------------------------------------------------------------
// LED test
// -----------------------------------------------------------------------------
static void led_test_init(void)
{
    uint32_t i;
    uint32_t ch_enable_mask = 0u;

    for (i = 0; i < LED_PWM_CHANNELS; i++) {
        ch_enable_mask |= (1u << i);
        pwm_write_duty(LED_PWM_BASE, i, 0u);
    }

    pwm_common_init(LED_PWM_BASE, LED_PWM_PERIOD, ch_enable_mask);
}

static uint32_t led_wave_duty(uint32_t phase)
{
    uint32_t sample = led_wave_table[phase % LED_WAVE_STEPS];
    return (sample * LED_PWM_PERIOD) / 1000u;
}

static void led_test_step(uint32_t step)
{
    uint32_t i;

    for (i = 0; i < LED_PWM_CHANNELS; i++) {
        uint32_t phase_offset = (i * LED_WAVE_STEPS) / LED_PWM_CHANNELS;
        uint32_t phase = (step + phase_offset) % LED_WAVE_STEPS;
        uint32_t duty = led_wave_duty(phase);
        pwm_write_duty(LED_PWM_BASE, i, duty);
    }

    pwm_apply(LED_PWM_BASE);
}

// -----------------------------------------------------------------------------
// Motor test
// -----------------------------------------------------------------------------
typedef enum
{
    MOTOR_STAGE_RAMP_UP = 0,
    MOTOR_STAGE_HOLD_TOP,
    MOTOR_STAGE_RAMP_DOWN,
    MOTOR_STAGE_BRAKE
} motor_stage_t;

static uint32_t motor_ramp_up_duty(uint32_t frame)
{
    if (frame >= MOTOR_RAMP_FRAMES) {
        frame = MOTOR_RAMP_FRAMES - 1u;
    }

    return ((frame + 1u) * MOTOR_MAX_DUTY) / MOTOR_RAMP_FRAMES;
}

static uint32_t motor_ramp_down_duty(uint32_t frame)
{
    if (frame >= MOTOR_RAMP_FRAMES) {
        frame = MOTOR_RAMP_FRAMES - 1u;
    }

    return MOTOR_MAX_DUTY - ((frame * MOTOR_MAX_DUTY) / MOTOR_RAMP_FRAMES);
}

static void motor_write_mode(uint32_t dir_mask, uint32_t brake_mask, uint32_t coast_mask)
{
    mmio_write32(MOTOR_PWM_BASE, REG_DIR_MASK, dir_mask);
    mmio_write32(MOTOR_PWM_BASE, REG_BRAKE_MASK, brake_mask);
    mmio_write32(MOTOR_PWM_BASE, REG_COAST_MASK, coast_mask);
}

static void motor_write_both_duty(uint32_t duty_a, uint32_t duty_b)
{
    pwm_write_duty(MOTOR_PWM_BASE, MOTOR_CH_A, duty_a);
    pwm_write_duty(MOTOR_PWM_BASE, MOTOR_CH_B, duty_b);
}

static void motor_commit(uint32_t dir_mask,
                         uint32_t brake_mask,
                         uint32_t coast_mask,
                         uint32_t duty_a,
                         uint32_t duty_b)
{
    motor_write_mode(dir_mask, brake_mask, coast_mask);
    motor_write_both_duty(duty_a, duty_b);
    pwm_apply(MOTOR_PWM_BASE);
}

static void motor_test_init(void)
{
    pwm_common_init(MOTOR_PWM_BASE, MOTOR_PWM_PERIOD, MOTOR_MASK_BOTH);

    // Start at zero duty, forward direction, not braking, not coasting
    motor_commit(MOTOR_MASK_BOTH, 0u, 0u, 0u, 0u);
}

static void motor_test_step(motor_stage_t *stage,
                            uint32_t *frame_count,
                            uint32_t *dir_mask)
{
    uint32_t duty;

    switch (*stage) {
        case MOTOR_STAGE_RAMP_UP:
            duty = motor_ramp_up_duty(*frame_count);
            motor_commit(*dir_mask, 0u, 0u, duty, duty);

            (*frame_count)++;
            if (*frame_count >= MOTOR_RAMP_FRAMES) {
                *frame_count = 0u;
                *stage = MOTOR_STAGE_HOLD_TOP;
            }
            break;

        case MOTOR_STAGE_HOLD_TOP:
            motor_commit(*dir_mask, 0u, 0u, MOTOR_MAX_DUTY, MOTOR_MAX_DUTY);

            (*frame_count)++;
            if (*frame_count >= MOTOR_HOLD_FRAMES) {
                *frame_count = 0u;
                *stage = MOTOR_STAGE_RAMP_DOWN;
            }
            break;

        case MOTOR_STAGE_RAMP_DOWN:
            duty = motor_ramp_down_duty(*frame_count);
            motor_commit(*dir_mask, 0u, 0u, duty, duty);

            (*frame_count)++;
            if (*frame_count >= MOTOR_RAMP_FRAMES) {
                *frame_count = 0u;
                *stage = MOTOR_STAGE_BRAKE;
            }
            break;

        case MOTOR_STAGE_BRAKE:
        default:
            motor_commit(*dir_mask, MOTOR_MASK_BOTH, 0u, 0u, 0u);

            (*frame_count)++;
            if (*frame_count >= MOTOR_BRAKE_FRAMES) {
                *frame_count = 0u;
                *stage = MOTOR_STAGE_RAMP_UP;
                *dir_mask = (*dir_mask == 0u) ? MOTOR_MASK_BOTH : 0u;
            }
            break;
    }
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------
int main(void)
{
    uint32_t led_step = 0u;
    uint32_t motor_frame_count = 0u;
    uint32_t motor_dir_mask = MOTOR_MASK_BOTH;
    motor_stage_t motor_stage = MOTOR_STAGE_RAMP_UP;

    printf("\nPWM split demo start\n");
    printf("MOTOR_PWM_BASE = 0x%08X\n", MOTOR_PWM_BASE);
    printf("LED_PWM_BASE   = 0x%08X\n", LED_PWM_BASE);

    led_test_init();
    motor_test_init();

    while (1) {
        led_test_step(led_step);
        led_step = (led_step + 1u) % LED_WAVE_STEPS;

        motor_test_step(&motor_stage, &motor_frame_count, &motor_dir_mask);

        usleep(FRAME_DELAY_US);
    }

    return 0;
}