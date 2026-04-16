//i2c_master_core.sv
//
//i2c master core based on Pong Chu Design from FPGA PROTOTYPING
//BY SYSTEMVERILOG EXAMPLES
//Several modifications have been done
//Reorganization for easy ready and easy modification
//additional signal to avoid ambiguity such as "ready"
//makes it easier to wrap with a generic MMIO Register wrapper
//also some safeguarding when choosing divisor
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
    parameter   int unsigned    BYTE_W      =   8,  
    parameter   int unsigned    CMD_W       =   3,
    parameter   logic   [DIVISOR_W-1:0] MIN_DIVISOR =   'd1)

    (
    input   logic                   clk,
    input   logic                   rst_n,

    input   logic   [DIVISOR_W-1:0] divisor,

    output  logic   [BYTE_W-1:0]    rx_data_o,
    input   logic   [BYTE_W-1:0]    tx_data_i,
    input   logic                   rd_last_i,  //if this is the last byte: send NACK else send ACK

    input   logic                   sda_in,
    output  logic                   sda_out,

    input   logic                   scl_in,
    output  logic                   scl_out,
  
    input   logic   [CMD_W-1:0]     cmd,
    output  logic                   cmd_illegal_o,
    input   logic                   cmd_valid_i,        //Register wrapper needs to assert this signal in order to write
    output  logic                   cmd_ready_o,        //can accept next cmd

    output  logic                   done_tick_o,        //byte-level command completed
    output  logic                   ack_o,              
    output  logic                   ack_valid_o,        //valid after WR_CMD
    output  logic                   rd_data_valid_o  ,   //valid after RD_CMD

    output  logic                   bus_idle_o,         //bus fully idle

    output  logic                   master_receiving);  //top-level should: sda =   (master_receiving   ||  sda_out)    ?   1'bz    :   1'b0;)
    


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

//--------------------------------------------------------------
//Registers
//--------------------------------------------------------------
state_t state_reg;
state_t state_next;

logic   [DIVISOR_W-1:0] tick_cnt_reg,   tick_cnt_next;  //register counts continuously and is cleared to zero whe the FSM exits the previous state. c_reg in book
logic   [DIVISOR_W-1:0] divisor_reg,    divisor_next;
logic   [DIVISOR_W-1:0] divisor_clamped;
logic   [DIVISOR_W-1:0] quarter_cnt,    half_cnt;

logic   [BYTE_W:0]    tx_reg,         tx_next;
logic   [BYTE_W:0]    rx_reg,         rx_next;
logic   [CMD_W-1:0]     cmd_reg,        cmd_next;

logic   [3:0]           bit_idx_reg,    bit_idx_next;   //keeps track of the number of data bits processed. bit_reg in book

logic                   sda_out_reg,    sda_out_next;
logic                   scl_out_reg,    scl_out_next;

logic   done_tick_int;
logic   receiving_f;
logic   nack; //remove
logic   data_phase;

//----------------------------------------------------------
//Legal event/command detection
//----------------------------------------------------------
logic   idle_start_fire;
logic   hold_wr_fire;
logic   hold_rd_fire;
logic   hold_stop_fire;
logic   hold_restart_fire;

logic   hold_cmd_fire;
logic   cmd_fire;

//S_IDLE accepts only START_CMD
assign  idle_start_fire =   (state_reg==S_IDLE) && cmd_valid_i  && (cmd==START_CMD);

//S_HOLD accepts WR_CMD
assign  hold_wr_fire    =   (state_reg==S_HOLD) &&  cmd_valid_i &&  (cmd==WR_CMD);

//S_HOLD accepts RD_CMD
assign  hold_rd_fire    =   (state_reg==S_HOLD) &&  cmd_valid_i &&  (cmd==RD_CMD);

//S_HOLD accepts STOP_CMD
assign  hold_stop_fire  =   (state_reg==S_HOLD) &&  cmd_valid_i &&  (cmd==STOP_CMD);

//S_HOLD accepts RESTART_CMD
assign  hold_restart_fire  =   (state_reg==S_HOLD) &&  cmd_valid_i &&  (cmd==RESTART_CMD);

//Any legal command accpeted while in S_HOLD
assign  hold_cmd_fire   =   hold_wr_fire||hold_rd_fire||hold_stop_fire||hold_restart_fire;

//Any legal comand accepted anywhere the FSM is allowed to accept a command
assign  cmd_fire        =   idle_start_fire||hold_cmd_fire;

//----------------------------------------------------------------------
//Illegal cmd pulse
//------------------------------------------------------------------------
always_comb
begin
    cmd_illegal_o   =   1'b0;

    if((state_reg==S_IDLE)  &&  cmd_valid_i &&  (cmd    !=  START_CMD))
        cmd_illegal_o   =   1'b1;

    if((state_reg==S_HOLD)      &&  cmd_valid_i &&
        (cmd    !=  WR_CMD)     &&  (cmd    !=  RD_CMD) &&
        (cmd    !=  STOP_CMD)   &&  (cmd    !=  RESTART_CMD))
        cmd_illegal_o   =   1'b1;
end

//------------------------------------------------------------------------
//clamp divisor to safe value
//-------------------------------------------------------------------------
always_comb
begin
    if(divisor  <   MIN_DIVISOR)
        divisor_clamped =   MIN_DIVISOR;
    else
        divisor_clamped =   divisor;
end

assign  quarter_cnt =   divisor_reg;
assign  half_cnt    =   {divisor_reg[DIVISOR_W-2:0], 1'b0}; //half = 2* quarter_cnt


//------------------------------------------------------------
//Sequential registers
//------------------------------------------------------------
always_ff   @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        state_reg       <=  S_IDLE;
        tick_cnt_reg    <=  '0;
        bit_idx_reg     <=  '0;
        cmd_reg         <=  START_CMD;
        tx_reg          <=  '0;
        rx_reg          <=  '0;
        divisor_reg     <=  MIN_DIVISOR;
        sda_out_reg     <=  1'b1;
        scl_out_reg     <=  1'b1;
    end
    else
    begin
        state_reg       <=  state_next;
        tick_cnt_reg    <=  tick_cnt_next;
        bit_idx_reg     <=  bit_idx_next;
        cmd_reg         <=  cmd_next;
        tx_reg          <=  tx_next;
        rx_reg          <=  rx_next;
        divisor_reg     <=  divisor_next;
        sda_out_reg     <=  sda_out_next;
        scl_out_reg     <=  scl_out_next;
    end
end

//-------------------------------------------------------
//next-state    logic
//------------------------------------------------------
always_comb
begin
    state_next      =   state_reg;
    
    unique  case    (state_reg)
    S_IDLE:
        begin
            if(idle_start_fire)
                state_next  =   S_START_1;
        end

    S_START_1:
        begin
            if(tick_cnt_reg==half_cnt)
                state_next  =   S_START_2;
        end

    S_START_2:
        begin
            if(tick_cnt_reg==quarter_cnt)
                state_next  =   S_HOLD;
        end

    S_HOLD:         //in progress; prepared for the next op
        begin
            if(hold_restart_fire)
                state_next  =   S_RESTART;
            else if(hold_stop_fire)
                state_next  =   S_STOP_1;
            else if(hold_wr_fire||hold_rd_fire)
                state_next  =   S_DATA_1;
        end

    S_RESTART:
        begin
            if(tick_cnt_reg==half_cnt)
                state_next  =   S_START_1;
        end

    S_STOP_1:
        begin
            if(tick_cnt_reg==half_cnt)
                state_next  =   S_STOP_2;
        end

    S_STOP_2:
        begin
            if(tick_cnt_reg==half_cnt)
                state_next  =   S_IDLE;
        end

    S_DATA_1:
        begin
            if(tick_cnt_reg==quarter_cnt)
                state_next  =   S_DATA_2;
        end

    S_DATA_2:
        begin
            if(tick_cnt_reg==quarter_cnt)
                state_next  =   S_DATA_3;
        end

    S_DATA_3:
        begin
            if(tick_cnt_reg==quarter_cnt)
                state_next  =   S_DATA_4;
        end

    S_DATA_4:
        begin
            if(tick_cnt_reg==quarter_cnt)
            begin
                if(bit_idx_reg==BYTE_W)
                    state_next  =   S_DATA_END;
                else
                    state_next  =   S_DATA_1;   
            end
        end

    S_DATA_END:
        begin
            if(tick_cnt_reg==quarter_cnt)
                state_next  =   S_HOLD;
        end
    default:
        begin
            //do nothing
        end
    endcase
end
//-------------------------------------------------------------
//update tick_cnt_next
//-------------------------------------------------------------
always_comb
begin
    tick_cnt_next   =   tick_cnt_reg    +   1'b1;

    if(cmd_fire)
            tick_cnt_next   =   '0;

    if  ((state_reg==S_START_1) ||(state_reg==S_RESTART)||
        (state_reg==S_STOP_1)   ||(state_reg==S_STOP_2))
    begin
        if(tick_cnt_reg==half_cnt)
            tick_cnt_next   =   '0;
    end

    if  ((state_reg==S_START_2) ||(state_reg==S_DATA_1)||
        (state_reg==S_DATA_2)   ||(state_reg==S_DATA_3)||
        (state_reg==S_DATA_4)   ||(state_reg==S_DATA_END))
    begin
        if(tick_cnt_reg==quarter_cnt)
            tick_cnt_next   =   '0;
    end
end

//-------------------------------------------------------------------
//Latch divisor only at IDLE when startign, whole transaction has same speed
//--------------------------------------------------------------------
always_comb
begin
    divisor_next    =   divisor_reg;
    
    if(idle_start_fire)
        divisor_next    =   divisor_clamped;
end

//----------------------------------------------------------------
//Latch command only when launch a legal command
//----------------------------------------------------------------
always_comb
begin
    cmd_next    =   cmd_reg;

    if(cmd_fire)
        cmd_next    =   cmd;
end

//---------------------------------------------------------------
//update bit_idx
//---------------------------------------------------------------
always_comb
begin
    bit_idx_next    =   bit_idx_reg;

    if(hold_wr_fire ||  hold_rd_fire)
            bit_idx_next    =   '0;


    if(state_reg==S_DATA_4  && tick_cnt_reg==quarter_cnt)
    begin
            if(bit_idx_reg < BYTE_W)
                bit_idx_next    =   bit_idx_next + 1'b1;
    end
end

//-------------------------------------------------------------
//TX shift register
//---------------------------------------------------------
always_comb
begin
    tx_next =   tx_reg;
    
    //Fire the write command: load 8-bit data + don't care ack slot
    if(hold_wr_fire)
        tx_next    =   {tx_data_i, 1'b1};

    //fire read command: upper bits don't matter, bit[0] becomes ack/NACK phase
    if(hold_rd_fire)
        tx_next =   {8'h00, rd_last_i};

    if((state_reg==S_DATA_4) && (tick_cnt_reg==quarter_cnt))
    begin
        if(bit_idx_reg < BYTE_W)
            tx_next    =   {tx_reg[BYTE_W-1:0],1'b0};
    end
end

//-------------------------------------------------------------
//RX shift register
//-------------------------------------------------------------
always_comb
begin
    rx_next =   rx_reg;
    begin
        if(hold_wr_fire||hold_rd_fire)
            rx_next =   '0;

        if((state_reg==S_DATA_2)  && (tick_cnt_reg==quarter_cnt))
            rx_next =   {rx_reg[BYTE_W-1:0],sda_in};
    end
end


//---------------------------------------------------------------
//update sda_out_next
//1 -> release line (top-level drives z)
//0 -> drive line low
//---------------------------------------------------------------
always_comb
begin
    sda_out_next    =   1'b1;
    
    if( (state_reg==S_START_1)  ||(state_reg==S_START_2)    ||
        (state_reg==S_HOLD)     ||(state_reg==S_DATA_END)   ||
        (state_reg==S_STOP_1))
        sda_out_next    =   1'b0;

    if( (state_reg==S_DATA_1)   ||  (state_reg==S_DATA_2)   ||
        (state_reg==S_DATA_3)   ||  (state_reg==S_DATA_4))
        sda_out_next    =   tx_reg[BYTE_W];
end

//----------------------------------------------------------------
//update scl_out_next
//1 -> release line (top-level drives z)
//0 -> drive line low
//----------------------------------------------------------------
always_comb
begin
    scl_out_next    =   1'b1;

    if( (state_reg==S_START_2)  ||(state_reg==S_HOLD)   ||
        (state_reg==S_DATA_1)   ||(state_reg==S_DATA_4) ||
        (state_reg==S_DATA_END))
        scl_out_next    =   1'b0;

end

//-----------------------------------------------------------------------------
//update done_tick_int
//-------------------------------------------------------------------------------
always_comb
begin
    done_tick_int   =   1'b0;
    if((state_reg==S_DATA_4) && (tick_cnt_reg==quarter_cnt) && (bit_idx_reg==BYTE_W))
        done_tick_int   =   1'b1;
end

//-----------------------------------------------------------------------------------
//defining when it's data phase
//-----------------------------------------------------------------------------------
assign  data_phase  =   (state_reg==S_DATA_1)   ||  (state_reg==S_DATA_2)   ||
                        (state_reg==S_DATA_3)   ||  (state_reg==S_DATA_4);

//set receiving flag if data is being transmitted and current cmd is read, and the current bit being dealt with is 0-7 OR
//in data phase and current cmd is write, and the current bit is bit 8 (9th bit is acknoledge bit, master will be receiving it.
assign receiving_f   =  ((data_phase)   &&  (cmd_reg==RD_CMD)   &&  (bit_idx_reg<BYTE_W))    ||  
                        ((data_phase)   &&  (cmd_reg==WR_CMD)   &&  (bit_idx_reg==BYTE_W));

//-----------------------------------------------------------------------------------
//Outputs
//-----------------------------------------------------------------------------------
assign  cmd_ready_o     =   (state_reg  ==  S_IDLE) || (state_reg   ==  S_HOLD);
assign  bus_idle_o      =   (state_reg  ==  S_IDLE);

assign  done_tick_o     =   done_tick_int;

assign  rx_data_o       =   rx_reg[BYTE_W:1];
assign  ack_o           =   rx_reg[0];      //obtained from slave in write
assign  ack_valid_o     =   done_tick_int   &&  (cmd_reg==WR_CMD);
assign  rd_data_valid_o =   done_tick_int   &&  (cmd_reg==RD_CMD);

assign  sda_out         =   sda_out_reg;
assign  scl_out         =   scl_out_reg;

//wrapper might need this information
assign  master_receiving    =   receiving_f;

//for future clock-stretch support
//and avoid unused warning
logic   unused_scl_in;
assign  unused_scl_in   =   slc_in;


endmodule











