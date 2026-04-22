#ifndef GPIO_REGS_H
#define GPIO_REGS_H

#include "user_define_system.h"
#include <stdint.h>

#define GPIO_REG_DATA_IN_OFFSET     0x00u
#define GPIO_REG_DATA_OUT_OFFSET    0x04u
#define GPIO_REG_DATA_OE_OFFSET     0x08u
#define GPIO_REG_RISE_IP_OFFSET     0x0Cu
#define GPIO_REG_FALL_IP_OFFSET     0x10u

void     set_tris(uint32_t gpio_base, uint32_t tris_mask);
uint32_t read_port(uint32_t gpio_base);
void     write_port(uint32_t gpio_base, uint32_t value);
uint32_t read_edge(uint32_t gpio_base);
void     clear_edge(uint32_t gpio_base, uint32_t edge_mask);
int      read_pin(uint32_t gpio_base, unsigned bit_index);
void     write_pin(uint32_t gpio_base, unsigned bit_index, int value);

#endif