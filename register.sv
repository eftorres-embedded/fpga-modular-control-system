module register(
						input logic clk,
						input logic set,
						input logic rst_n,
						input logic [7:0]din,
						output logic [7:0]dout);
						
						
logic [7:0]data_reg;

always_ff @(posedge clk or negedge rst_n)
begin
	if(!rst_n)
		data_reg <= 8'b0;
	else if(set)
		data_reg <= din;

end

assign dout = data_reg;

						
						
endmodule