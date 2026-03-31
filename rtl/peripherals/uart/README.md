# UART Peripheral

UART subsystem implementing transmit and receive engines with configurable baud rate generation.

## Architecture

* TX engine
* RX engine
* baud generator

## Components

* uart_tx_engine.sv
* uart_rx_engine.sv
* uart_baudgen.sv
* uart_port_ip.sv

## Features

* configurable baud rate
* modular RX/TX separation
* integration-ready with FIFO or MMIO

## Design Focus

* protocol correctness
* reusable serial interface
* clean separation of logic blocks
