/*
	Copyright (C), 2025, LGPL
	Author: ccapen@opencores.org
	V1.0
*/
module spi_master #(
	parameter	CPOL			= 0,	//SCLK = CPOL when spi is standby
	parameter	CPHA			= 1,	//when CPHA == 0, sample will occur in the first edge, 
										//when CPHA == 1, sample will occur in the second edge
	parameter	BITORDER		= "MSB_FIRST",	//"MSB_FIRST" "LSB_FIRST"
	parameter	DATAWIDTH		= 8,	//data width of interface, also bits of once transfer
	parameter	CLKDIV			= 8		//divide I_clk to generate O_sclk, must be even
) (
	input					I_clk,
	input					I_rstn,
	
	input					I_wvalid,
	input					I_transfer_end,		//enable to pullup O_csn; pulldown is automatic and unnecessary
												//share O_wready with I_wvalid, but lower priority
	input	[DATAWIDTH-1:0]	I_wdata,
	output					O_wready,
	output	[DATAWIDTH-1:0]	O_rdata,
	output					O_rvalid,
	
	output					O_csn,
	output					O_sclk,
	output					O_mosi,
	input					I_miso
);

localparam CNTWIDTH = $clog2(DATAWIDTH);


localparam IDLE		= 4'b0001;
localparam ENTR		= 4'b0010;
localparam RXTX		= 4'b0100;
localparam EXIT		= 4'b1000;

localparam IDLE_IND		= 4'd0;
localparam ENTR_IND		= 4'd1;
localparam RXTX_IND		= 4'd2;
localparam EXIT_IND		= 4'd3;

reg [3:0] R_state;
wire W_clk_en;

clk_valid #(
	.CLKDIVIDE		(CLKDIV/2),
	.REGMODE		("NOREG")
) clk_valid_u(
	.I_clk			(I_clk),
	.I_rstn			(!R_state[IDLE_IND]),
	
	.O_valid		(W_clk_en)
);

always@(posedge I_clk or negedge I_rstn)begin
	if(!I_rstn)
		R_state <= IDLE;
	else case (R_state)
		IDLE:	if(I_wvalid && O_wready)
					R_state <= ENTR;
				else 
					R_state <= IDLE;
		ENTR:	if(W_clk_en)
					R_state <= RXTX;
				else 
					R_state <= ENTR;
		RXTX:	if((!I_wvalid) && I_transfer_end && O_wready)
					R_state <= EXIT;
				else 
					R_state <= RXTX;
		EXIT:	if(W_clk_en)
					R_state <= IDLE;
				else 
					R_state <= EXIT;
		default:R_state <= IDLE;
	endcase
end

reg [CNTWIDTH+1:0] R_cnt;
reg [DATAWIDTH:0] R_wdata;
reg [DATAWIDTH-1:0] R_rdata;
reg R_rvalid;

always@(posedge I_clk or negedge I_rstn)begin
	if(!I_rstn)
		R_cnt <= {(CNTWIDTH+2){1'b0}};
	else if((!R_state[RXTX_IND]) || (I_wvalid && O_wready))
		R_cnt <= {(CNTWIDTH+2){1'b0}};
	else if((R_cnt == (DATAWIDTH*2)) || (!W_clk_en))
		R_cnt <= R_cnt;
	else 
		R_cnt <= R_cnt + 1'b1;
	
	if(!I_rstn)
		R_wdata <= {(DATAWIDTH+1){1'b0}};
	else if(I_wvalid && O_wready)
		R_wdata <= ((BITORDER == "MSB_FIRST") ^ (!CPHA)) ? {R_wdata[DATAWIDTH], I_wdata} : {I_wdata, R_wdata[0]};
	else if(R_state[RXTX_IND] && W_clk_en && (R_cnt[0] ^ CPHA))
		R_wdata <= (BITORDER == "MSB_FIRST") ? {R_wdata[DATAWIDTH-1:0], 1'b0} : {1'b0, R_wdata[DATAWIDTH:1]};
	else 
		R_wdata <= R_wdata;
	
	if(!I_rstn)
		R_rdata <= {DATAWIDTH{1'b0}};
	else if(W_clk_en && (R_cnt[0] ^ (!CPHA)))
		R_rdata <= (BITORDER == "MSB_FIRST") ? {R_rdata[DATAWIDTH-2:0], I_miso} : {I_miso, R_rdata[DATAWIDTH-1:1]};
	else 
		R_rdata <= R_rdata;
	
	if(!I_rstn)
		R_rvalid <= 1'b0;
	else 
		R_rvalid <= (R_cnt == (DATAWIDTH*2-1)) && W_clk_en;
end

assign O_wready = (R_state[IDLE_IND] || ((R_cnt >= (DATAWIDTH*2-1)) && W_clk_en));
assign O_rvalid = R_rvalid;
assign O_rdata = R_rdata;

assign O_csn = R_state[IDLE_IND];
assign O_sclk = R_cnt[0] ^ CPOL;
assign O_mosi = (BITORDER == "MSB_FIRST") ? R_wdata[DATAWIDTH] : R_wdata[0];


endmodule
