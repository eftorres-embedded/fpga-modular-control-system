#ifndef USER_DEFINE_SYSTEM_H
#define USER_DEFINE_SYSTEM_H

#include <stdint.h>

/*
 * Platform base addresses
 * Update these if the Platform Designer address map changes.
 */
#define MOTOR_PWM_BASE          0x00030000u
#define MOTOR_PWM_NUM_CHANNELS  2u

#define LED_PWM_BASE            0x00032000u
#define LED_PWM_NUM_CHANNELS    10u

#define I2C_BASE                0x00034000u

#define GPIO_BASE               0x00036000u

#endif