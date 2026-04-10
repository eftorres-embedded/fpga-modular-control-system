## 2026, April 10
The main UART module was made without documenting the original scope, it's started as a warm up for the whole project.
As it was the first one, it has feautures that are not necessary such as the huge FIFO, and it's missing others such as framing errord detection and stop-bit validation. 
I want to have UART ready to be used in a core, so I want to give it a MMIO register file, and wrap it with an AXI4 Lite interface. 
I would like to have two versions, one for fast streaming and one for ocassional console prints. 

For thas streaming, I want to use a buffered RAM window and use AXI4 Lite.
For the light, 'minimal' version, I would like to be able to connect it via AXI4 Lite, or just control it with a final state machine in case I don't have a processor in that core.

So, I will keep the core bus-agnostic and add AXI4-Lite only through wrappers /////2-byte skid buffer only in the buffered variant? how about the minimal? I want to decouple processor "random" access timing that's why I'm giving it a small buffer.

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

* uart_rx_engine.sv is clean for reuse, already has:
- input synchronizer
- 16x oversampling structure
- byte capture
- a one-byte output hold via output_buffer/output_valid
- stream handshake on the output 

* uart_baudgen.sv is clean for reuse

* uart_port_ip.sv


