/*
	Copyright (C), 2025, LGPL
	Author: ccapen@opencores.org
	V1.1
*/
module top_tb ();


reg R_clk;
reg R_rstn;
reg R_valid;

always #10 R_clk = !R_clk;

initial
begin
	R_clk = 1'b0;
	R_rstn = 1'b0;
	R_valid = 1'b0;
	#75 R_rstn = 1'b1;
	#40 R_valid = 1'b1;
	#20 R_valid = 1'b0;
end



wire W_csn;
wire W_sclk;
wire W_mosi;
wire W_miso;

spi_master #(
	.CPOL			(0),	//SCLK = CPOL when spi is standby
	.CPHA			(1),	//when CPHA == 0, sample will occur in the first edge, 
							//when CPHA == 1, sample will occur in the second edge
	.BITORDER		("MSB_FIRST"),	//"MSB_FIRST" "LSB_FIRST"
	.DATAWIDTH		(8),	//data width of interface, also bits of once transfer
	.CLKDIV			(8)		//divide I_clk to generate O_sclk, must be even
) spi_master_u(
	.I_clk				(R_clk),
	.I_rstn				(R_rstn),
	
	.I_wvalid			(R_valid),
	.I_transfer_end		(1'b1),		//enable to pullup O_csn
	.I_wdata			(8'hb5),
	.O_wready			(),
	.O_rdata			(),
	.O_rvalid			(),
	
	.O_csn				(W_csn),
	.O_sclk				(W_sclk),
	.O_mosi				(W_mosi),
	.I_miso				(W_miso)
);

spi_slave #(
	.CPOL			(0),	//SCLK = CPOL when spi is standby
	.CPHA			(1),	//when CPHA == 0, sample will occur in the first edge, 
							//when CPHA == 1, sample will occur in the second edge
	.BITORDER		("MSB_FIRST"),	//"MSB_FIRST" "LSB_FIRST"
	.DATAWIDTH		(8),	//data width of interface, also bits of once transfer
	.DRVMODE		("ADVANCE"),	//when I_clk frequency lower than (12 * I_sclk frequency), use "ADVANCE"; else use "NORMAL"
	.INTERVAL		(4)		//extend O_wready to wait I_wvalid
) spi_slave_u(
	.I_clk				(R_clk),	//I_clk frequency must higher than (4 * I_sclk frequency)
	.I_rstn				(R_rstn),

	.I_wvalid			(1'b1),
	.I_wdata			(8'h5a),
	.O_wready			(),
	.O_rvalid			(),
	.O_rdata			(),
	.O_transfer_end		(),

	.I_csn				(W_csn),
	.I_sclk				(W_sclk),
	.I_mosi				(W_mosi),
	.O_miso				(W_miso)
);


endmodule
