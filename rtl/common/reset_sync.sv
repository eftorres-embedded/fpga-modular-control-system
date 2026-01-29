module reset_sync (
							input  logic clk,
							input  logic arst_n,     // async reset in (active-low)
							output logic rst_n        // reset out (active-low), deasserts synchronously
);


logic [1:0] sync;

always_ff @(posedge clk or negedge arst_n)
begin
	if (!arst_n)
		sync <= 2'b00;           // assert immediately (async)
	else
      sync <= {sync[0], 1'b1}; // deassert on clock edges
end

assign rst_n = sync[1];


endmodule
