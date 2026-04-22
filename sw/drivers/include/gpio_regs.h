#ifndef GPIO_REGS_H
#define GPIO_REGS_H

#include "user_define_system.h"
#include <stdint.h>

#define GPIO_REG_DATA_IN_OFFSET     0x00u
#define GPIO_REG_DATA_OUT_OFFSET    0x04u
#define GPIO_REG_DATA_OE_OFFSET     0x08u
#define GPIO_REG_RISE_IP_OFFSET     0x0Cu
#define GPIO_REG_FALL_IP_OFFSET     0x10u

static inline volatile uint32_t *gpio_ptr(uint32_t gpio_base, uint32_t offset)
{
    return (volatile uint32_t *)(uintptr_t)(gpio_base + offset);
}

static inline uint32_t gpio_read_reg(uint32_t gpio_base, uint32_t offset)
{
    return *gpio_ptr(gpio_base, offset);
}

static inline void gpio_write_reg(uint32_t gpio_base, uint32_t offset, uint32_t value)
{
    *gpio_ptr(gpio_base, offset) = value;
}

static inline void set_tris(uint32_t gpio_base, uint32_t tris_mask)
{
    gpio_write_reg(gpio_base, GPIO_REG_DATA_OE_OFFSET, ~tris_mask);
}

static inline uint32_t read_port(uint32_t gpio_base)
{
    return gpio_read_reg(gpio_base, GPIO_REG_DATA_IN_OFFSET);
}

static inline void write_port(uint32_t gpio_base, uint32_t value)
{
    gpio_write_reg(gpio_base, GPIO_REG_DATA_OUT_OFFSET, value);
}

static inline uint32_t read_edge(uint32_t gpio_base)
{
    uint32_t rise_bits = gpio_read_reg(gpio_base, GPIO_REG_RISE_IP_OFFSET);
    uint32_t fall_bits = gpio_read_reg(gpio_base, GPIO_REG_FALL_IP_OFFSET);

    return rise_bits | fall_bits;
}

static inline void clear_edge(uint32_t gpio_base, uint32_t edge_mask)
{
    gpio_write_reg(gpio_base, GPIO_REG_RISE_IP_OFFSET, edge_mask);
    gpio_write_reg(gpio_base, GPIO_REG_FALL_IP_OFFSET, edge_mask);
}

static inline int read_pin(uint32_t gpio_base, unsigned bit_index)
{
    return (int)((read_port(gpio_base) >> bit_index) & 1u);
}

static inline void write_pin(uint32_t gpio_base, unsigned bit_index, int value)
{
    uint32_t port_value = gpio_read_reg(gpio_base, GPIO_REG_DATA_OUT_OFFSET);
    uint32_t bit_mask   = (uint32_t)1u << bit_index;

    if (value)
    {
        port_value |= bit_mask;
    }
    else
    {
        port_value &= ~bit_mask;
    }

    gpio_write_reg(gpio_base, GPIO_REG_DATA_OUT_OFFSET, port_value);
}

#endif