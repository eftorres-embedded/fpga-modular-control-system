# LCD Peripheral (HD44780 - Parallel Interface)

This module implements a parallel interface controller for HD44780-compatible character LCDs (e.g., 1602 displays), along with an adapter for streaming data from a FIFO.

The design is modular and split into:
- a **core LCD controller**
- an **adapter layer** for integrating with FIFO-based systems

---

## Modules

### `hd44780_parallel_lcd.sv`

Low-level LCD controller that directly drives the HD44780 interface.

**Responsibilities:**
- LCD initialization sequence
- Command/data write timing
- Control signal generation:
  - `RS` (Register Select)
  - `RW` (Read/Write, typically tied low)
  - `E` (Enable strobe)
- Data bus output (4-bit or 8-bit depending on configuration)

**Characteristics:**
- Fully synchronous design
- Internal timing control based on system clock
- Encapsulates LCD protocol and timing requirements

---

### `fifo_to_lcd_adapter.sv`

Adapter module that connects a FIFO to the LCD controller.

**Responsibilities:**
- Reads characters from a FIFO interface
- Converts FIFO data into LCD write operations
- Handles flow control between FIFO and LCD timing constraints

**Use Case:**
- Streaming text to LCD from:
  - UART input
  - CPU/MMIO writes
  - Other producer modules

---

## Architecture
```text
    +---------------------+
    |   FIFO (producer)   |
    +----------+----------+
               |
               v
    +---------------------+
    | FIFO -> LCD Adapter |
    | (flow control)      |
    +----------+----------+
               |
               v
    +---------------------+
    | HD44780 Controller  |
    | (timing + protocol) |
    +----------+----------+
               |
               v
          LCD Module
```

---

## Integration Notes

- The LCD controller operates at a much slower rate than typical system clocks.
- Timing constraints are handled internally; external modules should respect:
  - `ready` / `valid` style handshakes (if exposed)
  - FIFO backpressure

- The adapter ensures safe data transfer between:
  - fast producer domain (FIFO)
  - slow LCD interface

---

## Design Philosophy

This peripheral follows the same architectural pattern as other modules in the project:

- **Core logic isolated** (`hd44780_parallel_lcd.sv`)
- **Integration handled separately** (`fifo_to_lcd_adapter.sv`)
- No direct coupling to bus protocols (AXI/Avalon/etc.)

This allows:
- reuse in different systems
- easy extension (e.g., MMIO control later)
- clean separation of datapath vs control

---

## Future Improvements

- Add MMIO register interface (`lcd_regs.sv`)
- Add AXI4-Lite wrapper (`axi_lite_lcd.sv`)
- Support for cursor control and custom characters
- Optional buffering (internal FIFO)

---
