#ifndef MMIO_H
#define MMIO_H

#include <stdint.h>
#include <stddef.h>

/*
 * Portable memory-mapped IO helpers.
 * Assumes:
 * - base is a byte address
 * - offsets are byte offsets
 * - registers are naturally aligned
 */

static inline void mmio_write32(uint32_t base, uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(uintptr_t)(base + offset) = value;
}

static inline uint32_t mmio_read32(uint32_t base, uint32_t offset)
{
    return *(volatile const uint32_t *)(uintptr_t)(base + offset);
}

static inline void mmio_write16(uint32_t base, uint32_t offset, uint16_t value)
{
    *(volatile uint16_t *)(uintptr_t)(base + offset) = value;
}

static inline uint16_t mmio_read16(uint32_t base, uint32_t offset)
{
    return *(volatile const uint16_t *)(uintptr_t)(base + offset);
}

static inline void mmio_write8(uint32_t base, uint32_t offset, uint8_t value)
{
    *(volatile uint8_t *)(uintptr_t)(base + offset) = value;
}

static inline uint8_t mmio_read8(uint32_t base, uint32_t offset)
{
    return *(volatile const uint8_t *)(uintptr_t)(base + offset);
}

#endif /* MMIO_H */