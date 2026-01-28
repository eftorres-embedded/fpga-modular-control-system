//`define ENABLE_ADC_CLOCK
`define ENABLE_CLOCK1
//`define ENABLE_CLOCK2
//`define ENABLE_SDRAM
`define ENABLE_HEX0
`define ENABLE_HEX1
`define ENABLE_HEX2
`define ENABLE_HEX3
`define ENABLE_HEX4
`define ENABLE_HEX5
`define ENABLE_KEY
`define ENABLE_LED
`define ENABLE_SW
//`define ENABLE_VGA
//`define ENABLE_ACCELEROMETER
`define ENABLE_ARDUINO
`define ENABLE_GPIO

module modular_control_system_top(

	//////////// ADC CLOCK: 3.3-V LVTTL //////////
`ifdef ENABLE_ADC_CLOCK
	input 		          		ADC_CLK_10,
`endif
	//////////// CLOCK 1: 3.3-V LVTTL //////////
`ifdef ENABLE_CLOCK1
	input 		          		MAX10_CLK1_50,
`endif
	//////////// CLOCK 2: 3.3-V LVTTL //////////
`ifdef ENABLE_CLOCK2
	input 		          		MAX10_CLK2_50,
`endif

	//////////// SDRAM: 3.3-V LVTTL //////////
`ifdef ENABLE_SDRAM
	output		    [12:0]		DRAM_ADDR,
	output		     [1:0]		DRAM_BA,
	output		          		DRAM_CAS_N,
	output		          		DRAM_CKE,
	output		          		DRAM_CLK,
	output		          		DRAM_CS_N,
	inout 		    [15:0]		DRAM_DQ,
	output		          		DRAM_LDQM,
	output		          		DRAM_RAS_N,
	output		          		DRAM_UDQM,
	output		          		DRAM_WE_N,
`endif

	//////////// SEG7: 3.3-V LVTTL //////////
`ifdef ENABLE_HEX0
	output		     [7:0]		HEX0,
`endif
`ifdef ENABLE_HEX1
	output		     [7:0]		HEX1,
`endif
`ifdef ENABLE_HEX2
	output		     [7:0]		HEX2,
`endif
`ifdef ENABLE_HEX3
	output		     [7:0]		HEX3,
`endif
`ifdef ENABLE_HEX4
	output		     [7:0]		HEX4,
`endif
`ifdef ENABLE_HEX5
	output		     [7:0]		HEX5,
`endif

	//////////// KEY: 3.3 V SCHMITT TRIGGER //////////
`ifdef ENABLE_KEY
	input 		     [1:0]		KEY,
`endif

	//////////// LED: 3.3-V LVTTL //////////
`ifdef ENABLE_LED
	output		     [9:0]		LEDR,
`endif

	//////////// SW: 3.3-V LVTTL //////////
`ifdef ENABLE_SW
	input 		     [9:0]		SW,
`endif

	//////////// VGA: 3.3-V LVTTL //////////
`ifdef ENABLE_VGA
	output		     [3:0]		VGA_B,
	output		     [3:0]		VGA_G,
	output		          		VGA_HS,
	output		     [3:0]		VGA_R,
	output		          		VGA_VS,
`endif

	//////////// Accelerometer: 3.3-V LVTTL //////////
`ifdef ENABLE_ACCELEROMETER
	output		          		GSENSOR_CS_N,
	input 		     [2:1]		GSENSOR_INT,
	output		          		GSENSOR_SCLK,
	inout 		          		GSENSOR_SDI,
	inout 		          		GSENSOR_SDO,
`endif

	//////////// Arduino: 3.3-V LVTTL //////////
`ifdef ENABLE_ARDUINO
	inout 		    [15:0]		ARDUINO_IO,
	inout 		          		ARDUINO_RESET_N,
`endif

	//////////// GPIO, GPIO connect to GPIO Default: 3.3-V LVTTL //////////
`ifdef ENABLE_GPIO
	inout 		    [35:0]		GPIO
`endif
);



//=======================================================
//  REG/WIRE declarations
//=======================================================

wire [7:0]counter1;
wire dp;
wire rst_n;
wire arst_n = KEY[1] | KEY[0];
wire KEY0_pulse;

wire [7:0]lcd_data_o;
wire [7:0]lcd_data_i;
wire lcd_data_oe;
wire lcd_init_done;
wire lcd_host_ready; //wire for when lcd is ready for next transaction
wire lcd_host_valid;	//lcd's host has valid data
wire [8:0]lcd_txn;
wire [9:0]lcd_fifo_count;

wire fifo_rd_en;
wire fifo_empty;
wire [8:0]fifo_dout;

wire	baud_x16_tick;
wire	baud_1x_tick;



//=======================================================
//  Structural coding
//=======================================================
assign 		dp = 1'b1;

reset_sync	u_reset_synchronizer(
	.clk(MAX10_CLK1_50),
	.arst_n(arst_n),
	.rst_n(rst_n));

signal_to_pulse	u0(.clock(MAX10_CLK1_50), 	.signal(!KEY[0]), 	.pulse(KEY0_pulse));

hex_to_sseg			u_SW0(.hex(SW[3:0]), 	.dp_in(dp), 		.sseg(HEX0));

hex_to_sseg			u_SW1(.hex(SW[7:4]), 	.dp_in(dp), 		.sseg(HEX1));

hex_to_sseg			count0(.hex(lcd_fifo_count[3:0]), 	.dp_in(dp), 		.sseg(HEX2));

hex_to_sseg			count1(.hex(lcd_fifo_count[7:4]), 	.dp_in(dp), 		.sseg(HEX3));

hex_to_sseg			count2(.hex({1'b0,1'b0,lcd_fifo_count[9:8]}), 	.dp_in(dp), 		.sseg(HEX4));


counter	u_counter1(
.clk(MAX10_CLK1_50),
.rst_n(rst_n),
.d_in(SW[7:0]),
.set(1'b0),
.en(1),
.q_out(LEDR[7:0]));

/////////////////////////////////////////////
//lcd 1602 character
/////////////////////////////////////////////
hd44780_parallel_lcd		#(.CLOCK_HZ(50000000))											
	u_lcd(.clk(MAX10_CLK1_50),
	.rst_n(rst_n),
	.host_valid(lcd_host_valid), //host has valid data
	.host_rs(lcd_txn[8]),			//will the host send data or command (rs <=> register select)
	.host_data(lcd_txn[7:0]), 		//input data or command from host
	.host_ready(lcd_host_ready), 	//module finished transaction (ready to receive a new txn)
	
	//LCD interface
	.lcd_rs(GPIO[8]),
	.lcd_rw(GPIO[9]),
	.lcd_e(GPIO[10]),
	.lcd_data_o(lcd_data_o),
	.lcd_data_i(lcd_data_i),
	.lcd_data_oe(lcd_data_oe),
	.init_done(lcd_init_done));
								
	assign GPIO[7:0] = lcd_data_oe ? lcd_data_o	: 8'hzz;
	assign lcd_data_i	= GPIO[7:0];

/////////////////////////////////////////////	
// FIFO instance
/////////////////////////////////////////////
  sync_fifo #(
    .DEPTH(512),
    .WIDTH(9)) 
  u_fifo (
    .clk    (MAX10_CLK1_50),
    .srst_n (rst_n),

	//FIFO write side
    .wr_en  (KEY0_pulse),
    .din    (SW[8:0]),
    .full   (),
	 
	//FIFO read side
    .rd_en  (fifo_rd_en),
    .dout   (fifo_dout),
    .empty  (fifo_empty),

    .count  (lcd_fifo_count) // optional
  );
  
/////////////////////////////////////////////////
//fifo_to_lcd_adapter
///////////////////////////////////////////////
	fifo_to_lcd_adapter	u_adapter(
		.clk(MAX10_CLK1_50),
		.rst_n(rst_n),

		//FIFO read side
		.fifo_empty(fifo_empty),
		.fifo_dout(fifo_dout),
		.fifo_rd_en(fifo_rd_en),

		//LCD host side
		.init_done(lcd_init_done),
		.host_ready(lcd_host_ready),
		.host_valid(lcd_host_valid),
		.host_rs(lcd_txn[8]),
		.host_data(lcd_txn[7:0]));
		
//////////////////////////////////////////
//////////TX signals and testing ROM/////////
/////////////////////////////////////////////

//assign	GPIO[2]		=	tx_in_valid;
//assign	GPIO[3]		= 	tx_in_ready;
//assign	GPIO[4]		=	tx_busy;
//assign	GPIO[5]		=	uart_tx;
//assign	tx_in_data	=	8'hAA;

//logic analyzer
//assign GPIO[35] 	= rst_n;
//assign GPIO[0] 	= baud_1x_tick;
//assign GPIO[1] 	= baud_x16_tick;
//assign GPIO[34]	= rst_n;

//tx engine
logic tx_in_valid;
logic	tx_in_ready;
logic tx_busy;
logic	uart_tx;
logic	[7:0] tx_in_data;
	

//tester ROM
localparam int ROM_LEN = 4;
logic [7:0] rom [0:ROM_LEN-1];

initial begin
	rom[0] = 8'h55;
	rom[1] = 8'hAA;
	rom[2] = 8'h00;
	rom[3] = 8'hFF;
end

logic[$clog2(ROM_LEN)-1:0] rom_idx;

//Present current ROM byte continously
assign tx_in_data = rom[rom_idx];

//offer a byte wheenver tx is ready
assign tx_in_valid = tx_in_ready;

//advance ROM index only when the byte is acceptted
logic tx_fire;
assign tx_fire = tx_in_valid && tx_in_ready;

always_ff @(posedge MAX10_CLK1_50 or negedge rst_n)
begin
	if(!rst_n)
		rom_idx <= '0;
	else if(tx_fire)
	begin
		if(rom_idx == ROM_LEN-1)
			rom_idx <= '0;
		else
			rom_idx <= rom_idx + 1'b1;
	end
end


////////////////////////////////////////////
////////////RX Signasl//////////////////////
///////////////////////////////////////////

logic 		uart_rx;
logic			rx_out_valid;
logic			rx_out_ready;
logic	[7:0] rx_out_data;
logic			rx_busy;	


//assign		GPIO[7]			=	rx_out_valid;
//assign		rx_out_ready	=	1'b1;
//assign		GPIO[15:8]		=	rx_out_data;
//assign		GPIO[9]			=	rx_busy;


////////////////////////////////////////////
////////////ESP Wi-Fi Module////////////////
////////////////////////////////////////////
logic		esp_01s_en; 	//GPIO[13]
logic		esp_01s_rst;	//GPIO[14]
logic		esp_01s_tx;		//GPIO[11]
logic		esp_01s_rx;		//GPIO[12]

//alias for uart_rx and uart_tx;
assign	esp_01s_rx	=	uart_rx;
assign	uart_tx		=	esp_01s_tx;

assign	GPIO[11]		=	esp_01s_tx;
assign	esp_01s_rx	=	GPIO[12];
assign	GPIO[13]		=	esp_01s_en;
assign	GPIO[14]		=	esp_01s_rst;

assign esp_01s_en =	SW[0];

endmodule


