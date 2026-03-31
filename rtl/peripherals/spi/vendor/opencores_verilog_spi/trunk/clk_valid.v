/*
	Copyright (C), 2025, LGPL
	Author: ccapen@opencores.org
	V1.0
*/
module clk_valid #(
	parameter	CLKDIVIDE	= 2,	//must larger or equal 1
	parameter	REGMODE		= "NOREG"	// "NOREG" "OUTREG"
) (
	input		I_clk,
	input		I_rstn,
	
	output		O_valid
);

localparam CNTWIDTH = $clog2(CLKDIVIDE);

reg [CNTWIDTH-1:0] R_cnt;

wire W_valid;


always@(posedge I_clk or negedge I_rstn)
if(!I_rstn) R_cnt<={CNTWIDTH{1'b0}};
else if(W_valid) R_cnt<={CNTWIDTH{1'b0}};
else R_cnt<=R_cnt+1'b1;

assign W_valid = {R_cnt == (CLKDIVIDE - 1'b1)};

generate
	case(REGMODE)
	
		"NOREG":assign O_valid = W_valid;
		
		"OUTREG":begin
			reg R_valid;
			
			always@(posedge I_clk or negedge I_rstn)
			if(!I_rstn) R_valid<=1'b0;
			else R_valid<=W_valid;
			
			assign O_valid = R_valid;
		end
			
	endcase
endgenerate

endmodule
