# LCD Peripheral (HD44780)

Parallel LCD controller with FIFO adapter for character display.

## Components

Core:

* hd44780_parallel_lcd.sv

Adapter:

* fifo_to_lcd_adapter.sv

## Architecture

FIFO → Adapter → LCD Controller → Display

## Features

* HD44780-compatible interface
* internal timing management
* FIFO-based data input

## Design Focus

* bridging fast logic to slow peripherals
* timing abstraction
* reusable display interface
