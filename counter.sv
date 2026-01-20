module	counter(	input 	logic 		clk,
						input		logic			rst_n, 
						input 	logic [7:0]	d_in,
						input 	logic 		set,
						input 	logic 		en,
						output	logic [7:0]	q_out
						);
						
//signals
logic [7:0] shift_reg_internal;
logic [7:0] dout;
						
//instatiate register
register U0(
.clk(clk), 
.set(set), 	
.rst_n(rst_n), 
.din(shift_reg_internal[7:0]), 
.dout(dout[7:0]));						
						
always_comb
begin
	if(set)
		shift_reg_internal = d_in;
	else if(en)
		shift_reg_internal = dout + 1'b1;
	else
		shift_reg_internal = dout;

end						

assign q_out = dout;
						
endmodule