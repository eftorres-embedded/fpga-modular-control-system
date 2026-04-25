/*
 * SW[0]   : coast / enable
 *           0 = coast / disabled
 *           1 = enable selected motor channel
 *
 * SW[1]   : direction select
 *           0 = DIR_MASK_A
 *           1 = DIR_MASK_B
 *
 * SW[4:2] : duty select
 *           000 =   0
 *           001 = 100
 *           010 = 150
 *           011 = 200
 *           100 = 250
 *           101 = 300
 *           110 = 400
 *           111 = 500
 *
 * SW[5]   : motor select
 *           0 = motor channel 0 only
 *           1 = motor channel 1 only
 *
 * SW[9:6] : unused
 */
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

#include "pwm_regs.h"
#include "gpio_regs.h"
#include "seg7_debug_regs.h"

#define MOTOR_PWM_REG_DIR_MASK_OFFSET   0x40u
#define PWM_CTRL_ENABLE_MASK            0x00000001u

#define MOTOR_TEST_PERIOD               1000u

#define GPIO_SW_MASK                    0x000003FFu

#define DIR_MASK_A                      0x0u
#define DIR_MASK_B                      0x3u

static uint16_t get_switches(void)
{
    return (uint16_t)(read_port(GPIO_BASE) & GPIO_SW_MASK);
}

static uint32_t duty_from_sel(uint32_t sel)
{
    switch (sel & 0x7u)
    {
        case 0u: return 0u;
        case 1u: return 100u;
        case 2u: return 150u;
        case 3u: return 200u;
        case 4u: return 250u;
        case 5u: return 300u;
        case 6u: return 400u;
        default: return 500u;
    }
}

static void motor_disable_all(void)
{
    pwm_set_ch_enable(MOTOR_PWM_BASE, 0u);
    pwm_set_ctrl(MOTOR_PWM_BASE, 0u);
    pwm_apply(MOTOR_PWM_BASE);
}

static uint32_t pack_decimal_6digits(uint32_t value)
{
    uint8_t d5;
    uint8_t d4;
    uint8_t d3;
    uint8_t d2;
    uint8_t d1;
    uint8_t d0;

    d0 = (uint8_t)(value % 10u);
    value /= 10u;
    d1 = (uint8_t)(value % 10u);
    value /= 10u;
    d2 = (uint8_t)(value % 10u);
    value /= 10u;
    d3 = (uint8_t)(value % 10u);
    value /= 10u;
    d4 = (uint8_t)(value % 10u);
    value /= 10u;
    d5 = (uint8_t)(value % 10u);

    return seg7_pack_hex6(d5, d4, d3, d2, d1, d0);
}

static void seg7_show_duty_decimal(uint32_t duty)
{
    seg7_select_software();
    seg7_set_mode(SEG7_MODE_FULL6_HEX);
    seg7_set_sw_value(pack_decimal_6digits(duty));
}

static void motor_apply_switch_control(uint16_t sw)
{
    uint32_t enable_bit;
    uint32_t dir_sel;
    uint32_t duty_sel;
    uint32_t motor_sel;
    uint32_t dir_mask;
    uint32_t duty;
    uint32_t ch_enable;
    uint32_t duty0;
    uint32_t duty1;

    enable_bit = (sw >> 0) & 0x1u;
    dir_sel    = (sw >> 1) & 0x1u;
    duty_sel   = (sw >> 2) & 0x7u;
    motor_sel  = (sw >> 5) & 0x1u;

    dir_mask = dir_sel ? DIR_MASK_B : DIR_MASK_A;
    duty     = duty_from_sel(duty_sel);

    if (motor_sel == 0u)
    {
        ch_enable = enable_bit ? 0x1u : 0x0u;
        duty0     = duty;
        duty1     = 0u;
    }
    else
    {
        ch_enable = enable_bit ? 0x2u : 0x0u;
        duty0     = 0u;
        duty1     = duty;
    }

    pwm_set_period(MOTOR_PWM_BASE, MOTOR_TEST_PERIOD);
    pwm_set_duty_ch(MOTOR_PWM_BASE, 0u, duty0);
    pwm_set_duty_ch(MOTOR_PWM_BASE, 1u, duty1);
    PWM_REG32(MOTOR_PWM_BASE, MOTOR_PWM_REG_DIR_MASK_OFFSET) = dir_mask;
    pwm_set_ch_enable(MOTOR_PWM_BASE, ch_enable);
    pwm_set_ctrl(MOTOR_PWM_BASE, enable_bit ? PWM_CTRL_ENABLE_MASK : 0u);
    pwm_apply(MOTOR_PWM_BASE);

    seg7_show_duty_decimal(duty);
}

int main(void)
{
    uint16_t sw;
    uint16_t last_sw = 0xFFFFu;
    uint32_t enable_bit;
    uint32_t dir_sel;
    uint32_t duty_sel;
    uint32_t motor_sel;
    uint32_t duty;

    printf("Motor switch test\n");
    printf("SW0=en SW1=dir SW[4:2]=duty SW5=motor\n");
    printf("SEG7 shows current duty in decimal\n");
    fflush(stdout);

    set_tris(GPIO_BASE, 0xFFFFFFFFu);

    seg7_init();
    seg7_show_duty_decimal(0u);

    motor_disable_all();

    while (1)
    {
        sw = get_switches();

        if (sw != last_sw)
        {
            enable_bit = (sw >> 0) & 0x1u;
            dir_sel    = (sw >> 1) & 0x1u;
            duty_sel   = (sw >> 2) & 0x7u;
            motor_sel  = (sw >> 5) & 0x1u;
            duty       = duty_from_sel(duty_sel);

            motor_apply_switch_control(sw);

            printf("SW=0x%03X en=%lu dir=%lu duty=%lu motor=%lu\n",
                   (unsigned)sw,
                   (unsigned long)enable_bit,
                   (unsigned long)dir_sel,
                   (unsigned long)duty,
                   (unsigned long)motor_sel);
            fflush(stdout);

            last_sw = sw;
        }

        usleep(20000);
    }

    return 0;
}