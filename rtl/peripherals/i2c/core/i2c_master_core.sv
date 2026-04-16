//i2c_master_core.sv
//
//i2c master core based on Pong Chu Design from FPGA PROTOTYPING
//BY SYSTEMVERILOG EXAMPLES
//
//V1: simple master I2C to start the gyroscope and accelerometer, 
//this will only working a single master.
//I2C bus clock generation:
//each I2C clock cycle is composed of four phases
//so there are: (main-clock-frequency)/(4)*(i2c-clock-frequency)
//a counter can be used to track the number of elapsed clock cycles
//In this design, the start, restart and stop condidtion phases are half  of an I2C clock period. 
//for for these phases, the number of clock cycles are: (main-clock-frequency)/(2)*(i2c-clock-frequency)

module i2c_master   #(
    parameter   int unsigned    DIVISOR_W   =   16,
    parameter   int unsigned    DATA_W      =   9,  //8 data bits + 1 acknowledge bit
    parameter   int unsigned    CMD_W       =   3)

    (
    input   logic                   clk,
    input   logic                   rst_n,

    input   logic   [DIVISOR_W-1:0] divisor,
    output  logic                   busy,
    output  logic                   ready,
    output  logic                   ack,
    output  logic                   done_tick,

    output  logic   [7:0]           rx_data_o,
    input   logic   [7:0]           tx_data_i,

    input   logic                   sda_in,
    output  logic                   sda_out,

    input   logic                   scl_in,
    output  logic                   scl_out,
    
    input   logic   [CMD_W-1:0]     cmd,
    input   logic                   master_receiving);  //top-level should: sda =   (master_receiving   ||  sda_reg)    ?   1'bz    :   1'b0;)


//Symbolic constant
localparam  logic   [CMD_W-1:0] START_CMD   =   'h0;
localparam  logic   [CMD_W-1:0] WR_CMD      =   'h1;
localparam  logic   [CMD_W-1:0] RD_CMD      =   'h2;
localparam  logic   [CMD_W-1:0] STOP_CMD    =   'h3;
localparam  logic   [CMD_W-1:0] RESTART_CMD =   'h4;

//FSM state type
typedef enum    logic   [3:0]
{
    S_IDLE      =   4'h0,
    S_START_1   =   4'h1,
    S_START_2   =   4'h2,
    S_HOLD      =   4'h3,
    S_RESTART   =   4'h4,
    S_STOP_1    =   4'h5,
    S_STOP_2    =   4'h6,
    S_DATA_1    =   4'h7,
    S_DATA_2    =   4'h8,
    S_DATA_3    =   4'h9,
    S_DATA_4    =   4'hA,
    S_DATA_END  =   4'hB
}state_t;

//state registers
state_t state_reg;
state_t state_next;

logic   [DIVISOR_W-1:0] tick_cnt_reg,   tick_cnt_next;
logic   [DIVISOR_W-1:0] quarter_cnt,    half_cnt;
logic   [DATA_W-1:0]    tx_reg,         tx_next;
logic   [DATA_W-1:0]    rx_reg,         rx_next;
logic   [CMD_W-1:0]     cmd_reg,        cmd_next;
logic   [DATA_W-2:0]    bit_idx_reg,    bit_idx_next;

logic   sda_out_r, scl_out_r;

logic   done_tick_r,    ready_r;
logic   receiving_f;
logic   nack;
logic   data_phase

//----------------------------------------------------------
//output control logic
//----------------------------------------------------------

//buffer for sda and scl lines
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        sda_out =   1'b1;
        scl_out =   1'b1;
    end
    else
    begin
        sda_out =   sda_out_r;
        scl_out =   scl_out_r;
    end
end

//set receiving flag if data is being transmitted and current cmd is read, and the current bit being dealt with is 0-7 OR
//in data phase and current cmd is write, and the current bit is bit 8 (9th bit is acknoledge bit, master will be receiving it.
assign receiving_f   =  ((data_phase)   &&  (cmd_reg==RD_CMD)   &&  (bit_idx_reg<8))    ||  
                        ((data_phase)   &&  (cmd_reg==WR_CMD)   &&  (bit_idx_reg==8));

//wrapper might need this information
assign  master_receiving    =   receiving_f;


//output
assign  rx_data_o   =   rx_reg[8:1];
assign  ack         =   rx_reg[9];      //obtained from slave in write
assign  nack        =   tx_data_i[0];

//------------------------------------------------------------
//fsmd for transmitting three bytes
//------------------------------------------------------------

//registers
always_ff   (posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        state_reg       <=  S_IDLE;
        tick_cnt_reg    <=  '0;
        bit_idx_reg     <=  '0;
        cmd_reg         <=  START_CMD;
        tx_reg          <=  '0;
        rx_reg          <=  '0;
    end
    else
    begin
        state_reg       <=  state_next;
        tick_cnt_reg    <=  tick_cnt_reg;
        bit_idx_reg     <=  bit_idx_next;
        cmd_reg         <=  cmd_next;
        tx_reg          <=  tx_next;
        rx_reg          <=  rx_next;
    end

    











