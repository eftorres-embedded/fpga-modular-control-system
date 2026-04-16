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
    output  logic                   ready,
    output  logic                   ack,
    output  logic                   done_tick,

    output  logic   [DATA_W-2:0]    rx_data_o,
    input   logic   [DATA_W-2:0]    tx_data_i,

    input   logic                   sda_in,
    output  logic                   sda_out,

    input   logic                   scl_in,
    output  logic                   scl_out,
    
    input   logic   [CMD_W-1:0]     cmd,
    input   logic                   wr_i2c,             //Register wrapper needs to assert this signal in order to write
    output  logic                   master_receiving);  //top-level should: sda =   (master_receiving   ||  sda_reg)    ?   1'bz    :   1'b0;)


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

logic   [DIVISOR_W-1:0] tick_cnt_reg,   tick_cnt_next;  //register counts continuously and is cleared to zero whe the FSM exits the previous state. c_reg in book
logic   [DIVISOR_W-1:0] quarter_cnt,    half_cnt;
logic   [DATA_W-1:0]    tx_reg,         tx_next;
logic   [DATA_W-1:0]    rx_reg,         rx_next;
logic   [CMD_W-1:0]     cmd_reg,        cmd_next;
logic   [DATA_W-2:0]    bit_idx_reg,    bit_idx_next;   //keeps track of the number of data bits processed. bit_reg in book

logic                   sda_out_reg,    sda_out_next;
logic                   scl_out_reg,    scl_out_next;

logic   done_tick_int,    ready_int;
logic   receiving_f;
logic   nack;
logic   data_phase;

//----------------------------------------------------------
//output control logic
//----------------------------------------------------------

//buffer for sda and scl lines
always @(posedge clk or negedge rst_n)
begin
    if(!rst_n)
    begin
        sda_out_reg <=   1'b1;
        scl_out_reg <=   1'b1;
    end
    else
    begin
        sda_out_reg <=   sda_out_next;
        scl_out_reg <=   scl_out_next;
    end
end


//------------------------------------------------------------
//fsmd for transmitting three bytes
//------------------------------------------------------------

//registers
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
    end
    else
    begin
        state_reg       <=  state_next;
        tick_cnt_reg    <=  tick_cnt_next;
        bit_idx_reg     <=  bit_idx_next;
        cmd_reg         <=  cmd_next;
        tx_reg          <=  tx_next;
        rx_reg          <=  rx_next;
    end
end

assign  quarter_cnt =   divisor;
assign  half_cnt    =   {quarter_cnt[DIVISOR_W-2:0], 1'b0}; //half = 2* quarter_cnt

//next-state    logic
always_comb
begin
    state_next      =   state_reg;
    
    unique  case    (state_reg)
    S_IDLE:
        begin
            if(wr_i2c   &&  cmd==START_CMD)
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
            if(wr_i2c)
            begin
                case(cmd)
                    RESTART_CMD,    START_CMD:
                        state_next  =   S_RESTART;
                    STOP_CMD:
                        state_next  =   S_STOP_1;
                    default:
                        state_next  =   S_DATA_1;
                endcase
            end
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
                if(bit_idx_reg==8)
                    state_next  =  S_DATA_END;
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

//update tick_cnt_next
always_comb
begin
    tick_cnt_next   =   tick_cnt_reg    +   1'b1;

    if(state_reg==S_IDLE)
    begin
        if(wr_i2c && cmd==START_CMD)
            tick_cnt_next   =   '0;
    end

    if((state_reg==S_START_1)||(state_reg==S_RESTART)||(state_reg==S_STOP_1)||(state_reg==S_STOP_2))
    begin
        if(tick_cnt_reg==half_cnt)
            tick_cnt_next   =   '0;
    end

    if((state_reg==S_START_2)||(state_reg==S_DATA_1)||(state_reg==S_DATA_2)||(state_reg==S_DATA_3)||(state_reg==S_DATA_4)||(state_reg==S_DATA_END))
    begin
        if(tick_cnt_reg==quarter_cnt)
            tick_cnt_next   =   '0;
    end

    if(state_reg==S_HOLD)
    begin
        if(wr_i2c)
            tick_cnt_next   =   '0;
    end
end

//update bit_idx_next
always_comb
begin
    bit_idx_next    =   bit_idx_reg;

    if(state_reg==S_HOLD)
    begin
        if((cmd==RD_CMD)||(cmd==WR_CMD))
            bit_idx_next    =   '0;
    end

    if(state_reg==S_DATA_4)
    begin
        if(tick_cnt_reg==quarter_cnt)
        begin
            if(bit_idx_reg < 8)
                bit_idx_next    =   bit_idx_next + 1'b1;
        end

    end
end

//update tx_next
always_comb
begin
    tx_next =   tx_reg;

    if(state_reg==S_HOLD)
    begin
        if((cmd==RD_CMD)||(cmd==WR_CMD))
            tx_next    =   {tx_data_i,nack};
    end

    if(state_reg==S_DATA_4)
    begin
        if(tick_cnt_reg==quarter_cnt)
        begin
            if(bit_idx_reg < 8)
                tx_next    =   {tx_reg[7:0],1'b0};
        end

    end
end

//update rx_next
always_comb
begin
    rx_next =   rx_reg;
    begin
        if(state_reg==S_DATA_2)
        begin
            if(tick_cnt_reg==quarter_cnt)
                rx_next =   {rx_reg[7:0],sda_in};
        end
    end
end

//update cmd_next
always_comb
begin
    cmd_next    =   cmd_reg;

    if(state_reg==S_HOLD)
    begin
        if(wr_i2c)
            cmd_next    =   cmd;
    end
end

//update sda_out_next
always_comb
begin
    sda_out_next    =   1'b1;
    
    if((state_reg==S_START_1)||(state_reg==S_START_2)||(state_reg==S_HOLD)||(state_reg==S_DATA_END)||(state_reg==S_STOP_1))
        sda_out_next    =   1'b0;

    if((state_reg==S_DATA_1)||(state_reg==S_DATA_2)||(state_reg==S_DATA_3)||(state_reg==S_DATA_4))
        sda_out_next    =   tx_reg[8];

end

//update scl_out_next
always_comb
begin
    scl_out_next    =   1'b1;

    if((state_reg==S_START_2)||(state_reg==S_HOLD)||(state_reg==S_DATA_1)||(state_reg==S_DATA_4)||(state_reg==S_DATA_END))
        scl_out_next    =   1'b0;

end

//update ready_int
assign ready_int    =   ((state_reg==S_HOLD)||(state_reg==S_IDLE)) ?   1'b1    :   1'b0;

//update done_tick_int
always_comb
begin
    done_tick_int   =   1'b0;
    if(state_reg==S_DATA_4)
    begin
        if(tick_cnt_reg==quarter_cnt)
        begin
           if(bit_idx_reg==8)
                done_tick_int   =   1'b1; 
        end      
    end
end

//defining when it's data phase
assign  data_phase  =   (state_reg==S_DATA_1)||(state_reg==S_DATA_2)||(state_reg==S_DATA_3)||(state_reg==S_DATA_4);

//defining ready
assign  ready    =   ready_int;

//defining done_tick
assign  done_tick   =   done_tick_int;

//output
assign  rx_data_o   =   rx_reg[8:1];
assign  ack         =   rx_reg[0];      //obtained from slave in write
assign  nack        =   tx_data_i[0];
assign  sda_out     =   sda_out_reg;
assign  scl_out     =   scl_out_reg;

//set receiving flag if data is being transmitted and current cmd is read, and the current bit being dealt with is 0-7 OR
//in data phase and current cmd is write, and the current bit is bit 8 (9th bit is acknoledge bit, master will be receiving it.
assign receiving_f   =  ((data_phase)   &&  (cmd_reg==RD_CMD)   &&  (bit_idx_reg<8))    ||  
                        ((data_phase)   &&  (cmd_reg==WR_CMD)   &&  (bit_idx_reg==8));

//wrapper might need this information
assign  master_receiving    =   receiving_f;


endmodule











