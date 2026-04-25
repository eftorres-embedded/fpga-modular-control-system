#ifndef USER_DEFINE_SYSTEM_H
#define USER_DEFINE_SYSTEM_H

#include <stdint.h>

/*
 * Platform base addresses
 * Single source of truth for fixed MMIO bases.
 * Update these if the Platform Designer address map changes.
 */

#define ONCHIP_MEMORY_BASE         0x00000000u

#define SEG7_DEBUG_BASE            0x00051000u
#define I2C_0_BASE                 0x00052000u
#define MOTOR_PWM_BASE             0x00053000u
#define LED_PWM_BASE               0x00054000u
#define SPI_0_BASE                 0x00055000u
#define NIOSV_TIMER_SW_AGENT_BASE  0x00056000u
#define JTAG_UART_BASE             0x00056040u
#define GPIO_BASE                  0x00050000u

#endif /* USER_DEFINE_SYSTEM_H */