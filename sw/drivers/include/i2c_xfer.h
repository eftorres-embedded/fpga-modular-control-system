#ifndef I2C_XFER_H
#define I2C_XFER_H

#include <stdint.h>
#include <stddef.h>

#include "i2c_regs.h"

/*----------------------------------------------------------------------------
 * Raw device transfers
 *----------------------------------------------------------------------------*/
i2c_status_t i2c_write_bytes(uint8_t addr7,
                             const uint8_t *data,
                             size_t len);

i2c_status_t i2c_write_bytes_timeout(uint8_t addr7,
                                     const uint8_t *data,
                                     size_t len,
                                     uint32_t timeout_poll_count);

i2c_status_t i2c_read_bytes(uint8_t addr7,
                            uint8_t *data,
                            size_t len);

i2c_status_t i2c_read_bytes_timeout(uint8_t addr7,
                                    uint8_t *data,
                                    size_t len,
                                    uint32_t timeout_poll_count);

/*----------------------------------------------------------------------------
 * Common register-style transfers
 *----------------------------------------------------------------------------*/
i2c_status_t i2c_reg_write8(uint8_t addr7,
                            uint8_t reg,
                            uint8_t value);

i2c_status_t i2c_reg_write8_timeout(uint8_t addr7,
                                    uint8_t reg,
                                    uint8_t value,
                                    uint32_t timeout_poll_count);

i2c_status_t i2c_reg_read8(uint8_t addr7,
                           uint8_t reg,
                           uint8_t *value);

i2c_status_t i2c_reg_read8_timeout(uint8_t addr7,
                                   uint8_t reg,
                                   uint8_t *value,
                                   uint32_t timeout_poll_count);

i2c_status_t i2c_reg_write_bytes(uint8_t addr7,
                                 uint8_t reg,
                                 const uint8_t *data,
                                 size_t len);

i2c_status_t i2c_reg_write_bytes_timeout(uint8_t addr7,
                                         uint8_t reg,
                                         const uint8_t *data,
                                         size_t len,
                                         uint32_t timeout_poll_count);

i2c_status_t i2c_reg_read_bytes(uint8_t addr7,
                                uint8_t reg,
                                uint8_t *data,
                                size_t len);

i2c_status_t i2c_reg_read_bytes_timeout(uint8_t addr7,
                                        uint8_t reg,
                                        uint8_t *data,
                                        size_t len,
                                        uint32_t timeout_poll_count);

#endif /* I2C_XFER_H */