## 2026, April 10
The main UART module was made without documenting the original scope, it's started as a warm up for the whole project.
As it was the first one, it has feautures that are not necessary such as the huge FIFO, and it's missing others such as framing errord detection and stop-bit validation. 
I want to have UART ready to be used in a core, so I want to give it a MMIO register file, and wrap it with an AXI4 Lite interface. 
I would like to have two versions, one for fast streaming and one for ocassional console prints. 

For thas streaming, I want to use a buffered RAM window and use AXI4 Lite.
For the light, 'minimal' version, I would like to be able to connect it via AXI4 Lite, or just control it with a final state machine in case I don't have a processor in that core.

So, I will keep the core bus-agnostic and add AXI4-Lite only through wrappers 

The current modules I have is:
- uart_baudgen.sv
- uart_tx_engine.sv
- uart_rx_engine.sv
- top wrapper -uart_port_ip.sv

## Modifications Planned
* uart_tx_engine.sv is clean for reuse, it already has:
- stream-style input
- no bus baked in
- protocol FSM is isolated
* `Keep as shared core`

* uart_rx_engine.sv is clean for reuse, already has:
- input synchronizer
- 16x oversampling structure
- byte capture
- a one-byte output hold via output_buffer/output_valid
- stream handshake on the output 
* Limitation: no framing error/stop-bit validation flag
- Keep the current engine logic
- add framing_err_pulse
- break_detect

* uart_baudgen.sv is clean for reuse

* uart_port_ip.sv doesn't match our goal yet, it currently is:
- TX engine direct stream input
- RX engine feeding a 64-byte RX FIFO
- Extra ouput staging aroudn that FIFO
* What it currently does: Mixes baude gen, shared cores, RX FIFO policy, FIFO-to-stream output stage
- This file can be use as the base for uart_minimal.sv
- - We must
    -   ranem it to uart_minimal.sv
    -   remove the 64-byte sync_fifo
    -   remove the FIFO refill output-stage circuitry
    -   wirting RX engine stream directly outward

The current top is not a buffered RAM-window UART
Missing:
- TX RAM window
- RX RAM window
- register file/MMIO block
- interrupts
- AXI4-Lite wrapper
- 2-byte TX skid buffer
- 2-byte RX skid buffer
- Software-visible status/error handling

## What should be done in summary:
### For implementations: uart_minimal.sv & uart_buffered.sv
- uart_baudgen.sv
- uart_tx_engine.sv
- uart_rx_engine.sv
- Add a `new` uart_skid2.sv

### For uart_minimal.sv
- instantiate baudgen
- instantiate tx_engine
- instantiate rx_engine
- no RAM windows
- no AXI
- no interrupts
- no internal RX FIFO
- 1-byte elastic buffer
it should work in summary
```text
tx stream   ->  1-byte elastic buffer   ->   uart_tx_engine  -> uart_tx pin
uart_rx pin ->                               uart_rx_engine  -> rx stream

with baudgen shared by both engines
```

### For uart_buffered.sv
- This module should be bus-agnostic 
- instantiate baugen
- instantiate tx_engine
- instantiate rx_engine
- instantiate TX 2-byte skid
- instantiate RX 2-byte skid

in summary:

```text
TX launcher stream  ->  tx_skid2        ->  uart_tx_engine  ->  uart_tx pin
uart_rx pin         ->  uart_rx_engine  ->  rx_skid2        ->  RX capture stream
```
### uart_tx_ram_window.sv
Owns the software-to-UART buffering side:
- TX RAM storage
- software write path into the TX window
- launch/read pointer
- queued-byte count
- empty/full status
- tx_done pulse/sticky status generation
- stream output toward TX skid/ TX engine
It should own:
* tx_mem[]
* tx_wr_ptr
* tx_rd_ptr
* tx_count
* tx_empty
* tx_full
* tx_done_pulse
* tx_done_sticky
* stream output toward TX skid
MMIO-side inputs
- software write enable
- sofware write address/index
- software write data
- maybe a comand like tx_commit_len
UART-side stream outputs
* tx_out_valid
* tx_out_ready
* tx_out_data

### uart_rx_ram_window.sv
Owns the UART-to-software buffering side:
- RX RAM storage
- hardware capture path into the RX window
- write pointer
- software consume/read pointer
- queued-byte count
- data-available/full/overflow status
- RX-related event pulses
It should own:
* rx_mem[]
* rx_wr_ptr
* rx_rd_ptr
* rx_count
* rx_empty
* rx_full
* rx_overflow_pulse
* rx_overflow_sticky
* rx_data_available_pulse
* optional newline detect
UART-side stream outputs
- rx_in_valid
- rx_in_ready
- rx_in_data
MMIO-side inputs
* software read address/index
* rx_pop
* rx_clear
* rx_ack_overflow


### uart_buffered_regs.sv
This is where the buffered design will live:
- software-visible register map
- instantiate TX RAM window
- instantiate RX RAM window
- occupancy/state counter
- interrrupt generation
- overflow/statusbits

### axi_lite_uart_buffered.sv
Just a thin wrapper
- AXI4-Lite decode/handshake
- convert AXI transactions to your internal MMIO/register interrface
- instantiate uart_buffered_regs.sv

## File-level organization proposition
```text
uart_baudgen.sv
uart_tx_engine.sv
uart_rx_engine.sv
uart_skid2.sv

uart_minimal.sv
optional uart_minimal_regs.sv
optional axi_lite_uart_minimal.sv

uart_buffered.sv
uart_tx_ram_window.sv
uart_rx_ram_window.sv
uart_buffered_regs.sv
axi_lite_uart_buffered.sv
```

## uart_minimal layout
```text
+------------------+        +---------------------------+        +---------------------------+        +-----------+
|  TX stream in    | -----> | 1-byte TX elastic buffer  | -----> |      uart_tx_engine       | -----> | uart_tx   |
|------------------|        |---------------------------|        |---------------------------|        | pin       |
| tx_valid         |        | holds one pending byte    |        | stream-to-serial TX FSM   |        +-----------+
| tx_ready         |        | decouples random writes   |        | start/data/stop bits      |
| tx_data[7:0]     |        | from TX engine timing     |        | tx_busy                   |
+------------------+        +---------------------------+        +---------------------------+
                                                                                 ^
                                                                                 |
                                                                                 |
                                                       +-------------------------+-------------------------+
                                                       |                    uart_baudgen                   |
                                                       |---------------------------------------------------|
                                                       | clk, rst_n                                        |
                                                       | baud_en                                           |
                                                       | div_x16                                           |
                                                       |---------------------------------------------------|
                                                       | baud_x16_tick                                     |
                                                       | baud_1x_tick                                      |
                                                       +---------------------------------------------------+
                                                                                |
                                                                                |
                                                                                v
+-----------+                                                  +---------------------------+        +------------------+
| uart_rx   | -----------------------------------------------> |      uart_rx_engine       | -----> |  RX stream out   |
| pin       |                                                  |---------------------------|        |------------------|
+-----------+                                                  | synchronizer              |        | rx_valid         |
                                                               | 16x oversampling          |        | rx_ready         |
                                                               | byte capture              |        | rx_data[7:0]     |
                                                               | 1-byte output hold        |        +------------------+
                                                               | rx_busy                   |
                                                               +---------------------------+

```                    




## uart_buffered layout
```txt
+---------------------------+      +---------------------------+
|       axi_lite_uart       | ---> |         uart_regs         |
|---------------------------|      |---------------------------|
| thin AXI wrapper          |      | MMIO decode               |
| AXI handshake             |      | control regs              |
| MMIO req/rsp bridge       |      | baud_div reg              |
+---------------------------+      | status / irq regs         |
                                   | readback mux              |
                                   +---------------------------+
                                              |
                                              |
                      +-----------------------+-------------------------+                                                  
                      |                                                  |
                      |                                                  |
                      v                                                  v
    +----------------------------------+                +----------------------------------+            
    |        uart_rx_ram_window        |                |        uart_tx_ram_window        |            
    |----------------------------------|                |----------------------------------|            
    | RX RAM storage                   |                | TX RAM storage                   |            
    | HW capture path                  |                | SW write path                    |            
    | rx_wr_ptr / rx_rd_ptr            |                | tx_wr_ptr / tx_rd_ptr            |            
    | rx_count / empty / full          |                | tx_count / empty / full          |            
    | rx_overflow / data_avail         |                | tx_done pulse / sticky           |            
    | RX software read / pop / clear   |                | TX launcher stream output        |            
    +----------------------------------+                +----------------------------------+            
                    ^                                                   |
                    |                                                   | TX launcher stream 
                    |                                                   v                                                 
                    |                                   +---------------------------+      +---------------------------+  
                    |                                   |         tx_skid2          |      |      uart_tx_engine       |
                    |                                   |---------------------------|      |---------------------------|
                    |                                   | 2-byte TX elastic buffer  |      | stream-to-serial TX FSM   |
                    |                                   | decouples TX launcher     |----->| start/data/stop bits      |-------------------------> uart_tx pin
                    |RX capture stream                  +---------------------------+      | tx_busy                   |
                    |                                                                      +---------------------------+
                    |                                                                                   ^
                    |                                                                                   |
                    |                                                                                   | 
                    |                                                                                   |
                    |                                                                                   |
                    v                                                                                   |baud_x16_tick
        +---------------------------+                                                                   |
        |         rx_skid2          |                                                                   |
        |---------------------------|                                                                   |            
        | 2-byte RX elastic buffer  |                                                                   |
        | decouples RX capture      |                                                       +---------------------------+
        +---------------------------+                                                       |       uart_baudgen        |
                    ^                                                                       |---------------------------|
                    |                                                                       | clk, rst_n                |
                    |                                                                       | baud_en                   |
                    |                                                                       | div_x16                   |
                    |                                                                       | baud_x16_tick             |
                    |                                                                       | baud_1x_tick              |
                    |                                                                       +---------------------------+
                    |                                                                                   |
                    |                                                                                   |
                    |                                                                                   | baud_x16_tick
                    |                                                                                   |
                    |                                                                                   v
                    |                                                                       +---------------------------+      
                    |                                                                       |       uart_rx_engine      |      
                    |                                                                       |---------------------------|      
                    ----------------------------------------------------------------------- |                           |
                                                                                            | 16x oversampling          |---------->uart_rx pin
                                                                                            | byte capture              |      
                                                                                            | 1-byte output hold        |
                                                                                            | rx_busy                   |
                                                                                            +---------------------------+
```