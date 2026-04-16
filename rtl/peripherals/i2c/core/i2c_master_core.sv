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

module i2c_master(
    input   logic           clk,
    input   logic           rst_n,

    input   logic   [15:0]  prescaler,
    output  logic           busy,
    output  logic           ready,
    output  logic           ack,
    output  logic           done_tick,

    output  logic   [7:0]   rx_data_o,
    input   logic   [7:0]   tx_data_i,

    input   logic           sda_in,
    output  logic           sda_out,

    input   logic           scl_in,
    output  logic           scl_out);

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

    state_t current_state;
    state_t next_state;

    



