#include "gpio_regs.h"

/*
 * Internal low-level MMIO helpers.
 * These stay local to this file so the public API stays simple.
 */
static volatile uint32_t *gpio_ptr(uint32_t gpio_base, uint32_t offset)
{
    return (volatile uint32_t *)(uintptr_t)(gpio_base + offset);
}

static uint32_t gpio_read_reg(uint32_t gpio_base, uint32_t offset)
{
    return *gpio_ptr(gpio_base, offset);
}

static void gpio_write_reg(uint32_t gpio_base, uint32_t offset, uint32_t value)
{
    *gpio_ptr(gpio_base, offset) = value;
}

/*
 * Set pin direction using PIC-style TRIS semantics:
 * bit = 1 -> input
 * bit = 0 -> output
 *
 * Hardware uses OE semantics internally:
 * bit = 1 -> drive output
 * bit = 0 -> input / not driven
 *
 * So we invert before writing the OE register.
 */
void set_tris(uint32_t gpio_base, uint32_t tris_mask)
{
    gpio_write_reg(gpio_base, GPIO_REG_DATA_OE_OFFSET, ~tris_mask);
}

/*
 * Read the full normalized input port.
 * Each bit reflects the current pin state after input polarity handling.
 */
uint32_t read_port(uint32_t gpio_base)
{
    return gpio_read_reg(gpio_base, GPIO_REG_DATA_IN_OFFSET);
}

/*
 * Write the full output register.
 * This sets the value that will be driven on pins configured as outputs.
 */
void write_port(uint32_t gpio_base, uint32_t value)
{
    gpio_write_reg(gpio_base, GPIO_REG_DATA_OUT_OFFSET, value);
}

/*
 * Read edge-pending status.
 * A bit is set if either a rising or falling edge was latched on that pin.
 */
uint32_t read_edge(uint32_t gpio_base)
{
    uint32_t rise_bits = gpio_read_reg(gpio_base, GPIO_REG_RISE_IP_OFFSET);
    uint32_t fall_bits = gpio_read_reg(gpio_base, GPIO_REG_FALL_IP_OFFSET);

    return rise_bits | fall_bits;
}

/*
 * Clear edge-pending status.
 * Writing 1 clears the corresponding pending bit in both rise/fall registers.
 */
void clear_edge(uint32_t gpio_base, uint32_t edge_mask)
{
    gpio_write_reg(gpio_base, GPIO_REG_RISE_IP_OFFSET, edge_mask);
    gpio_write_reg(gpio_base, GPIO_REG_FALL_IP_OFFSET, edge_mask);
}

/*
 * Read one pin from the normalized input port.
 * Returns 1 if high, 0 if low.
 */
int read_pin(uint32_t gpio_base, unsigned bit_index)
{
    return (int)((read_port(gpio_base) >> bit_index) & 1u);
}

/*
 * Update one output bit and leave the other output bits unchanged.
 */
void write_pin(uint32_t gpio_base, unsigned bit_index, int value)
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