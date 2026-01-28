//////////////////////////////////////////////////////////////////////////////////////
//
//				Synchrounous FIFO (single-clock) interface
//
//	-A write transaction occurs on a rising clk edge when (wr_en && !full)
// -A read transaction occurs on a rising clk edge when (rd_en && !empty)
// -Registred-output FIFO: dout updates on the cycle a read ouccurs, when empty==1,
// dout is not valid (typically holds last value read)
// -srst_n should be synchronized with the same clock domain externally
//	to add: fifo_to_stream_stable.sv  wrapper for AXI out_valid signal
/////////////////////////////////////////////////////////////////////////////////////

module sync_fifo #(
	parameter int unsigned	DEPTH = 512,
	parameter int unsigned	WIDTH = 9)
	(
	input		logic					clk,
	input		logic					srst_n,	//expecting synchronized reset
	
	input		logic 				wr_en,	// produces asserts when wr_data is valid, ingnored when full
	input		logic [WIDTH-1:0] din,		// Data input written into FIFO when (wr_en && !full)
	output	logic					full,		//	FIFO asserts when FIFO is full

	
	input		logic					rd_en,	// consumer asserts when it wants to pop one entry, ignored when empty
	output	logic	[WIDTH-1:0]	dout,		// Data output, updates on successful read (rd_en && !empty)
	output	logic					empty,
	
	output	logic	[$clog2(DEPTH+1)-1:0] count); //occupancy count, for debug purposes [9:0] count;
	
	localparam int unsigned ADDR_WIDTH	= $clog2(DEPTH); //clog2(512) => 9
	//localparam int unsigned COUNT_WIDTH = $clog2(DEPTH + 1)
	
	//memory
	logic [WIDTH-1:0] mem [0:DEPTH-1];
	
	//Pointers (they will warp naturally because the Depth is a power-of-two)
	//being a power of two and having a natural wrap around is what makes it a circular buffer
	logic [ADDR_WIDTH-1:0] wr_ptr;
	logic [ADDR_WIDTH-1:0] rd_ptr;
	
	//Qualified operations (validate the rd_en and wr_en input signals)
	logic do_write;
	logic do_read;
	
	assign empty	=	(count == '0);
	assign full		=	(count == DEPTH[$clog2(DEPTH+1)-1:0]);
	
	assign do_write	=	wr_en && !full;
	assign do_read		=	rd_en && !empty; 
	
	//sequential logic (single clock, synchrnous reset)
	always_ff	@(posedge clk)
	begin
		if(!srst_n)
		begin
			wr_ptr	<=	'0;
			rd_ptr	<=	'0;
			count		<=	'0;
			dout		<=	'0;
		end
		
		else
		begin
		//Write path
			if(do_write)
			begin
				mem[wr_ptr]	<= din;
				wr_ptr		<=	wr_ptr + 1'b1;
			end
			
		//Read Path	
			if(do_read)
			begin
				dout		<=	mem[rd_ptr];
				rd_ptr	<=	rd_ptr + 1'b1;
			end
			
		//Occupancy update
			unique case	({do_write, do_read})
				2'b10:	count <= count + 1'b1; //write only
				2'b01:	count <=	count - 1'b1; //read only
				default:	count <= count;		  //both or neither
			endcase
		end
	end
	
				
endmodule