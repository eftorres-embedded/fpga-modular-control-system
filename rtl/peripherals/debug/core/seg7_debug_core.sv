//seg7_debug_core.sv
module  seg7_debug_core(
    input   logic           enable_i,
    input   logic   [23:0]  value_i,
    input   logic   [2:0]   mode_i,
    input   logic   [5:0]   dp_n_i, //active-low request
    input   logic   [5:0]   blank_i,    //1 = blank digit

    output  logic   [7:0]   hex5_o,
    output  logic   [7:0]   hex4_o,
    output  logic   [7:0]   hex3_o,
    output  logic   [7:0]   hex2_o,
    output  logic   [7:0]   hex1_o,
    output  logic   [7:0]   hex0_o);

    localparam  logic   [2:0]   MODE_FULL6_HEX  =   3'd0;
    localparam  logic   [2:0]   MODE_SPLIT2X12  =   3'd1;
    localparam  logic   [2:0]   MODE_SPLIT3X8   =   3'd2;
    localparam  logic   [2:0]   MODE_DIGIT_RAW  =   3'd3;

    logic   [3:0]   dig5, dig4, dig3, dig2, dig1, dig0;
    logic   [5:0]   default_dp_n;
    logic   [5:0]   final_dp_n;

    logic   [7:0]   hex5_raw, hex4_raw, hex3_raw, hex2_raw, hex1_raw, hex0_raw;

    always_comb
    begin
        dig5    =   value_i[23:20];
        dig4    =   value_i[19:16];
        dig3    =   value_i[15:12];
        dig2    =   value_i[11:8];
        dig1    =   value_i[7:4];
        dig0    =   value_i[3:0];

    unique  case    (mode_i)
        MODE_FULL6_HEX: default_dp_n    =   6'b111111;  //all off
        MODE_SPLIT2X12: default_dp_n    =   6'b110111;
        MODE_SPLIT3X8:  default_dp_n    =   6'b101011;
        MODE_DIGIT_RAW: default_dp_n    =   6'b111111;
        default:        default_dp_n    =   6'b111111;
    endcase

    //active-low convetion:
    //0 in either source turns the decimal point on
    //final_dp_n    =   default_dp_n    &   dp_n_i;
    end

    hex_to_sseg u_hex5  (.hex(dig5),    .dp_in(final_dp_n[5]),  .sseg(hex5_raw));
    hex_to_sseg u_hex4  (.hex(dig4),    .dp_in(final_dp_n[4]),  .sseg(hex4_raw));
    hex_to_sseg u_hex3  (.hex(dig3),    .dp_in(final_dp_n[3]),  .sseg(hex3_raw));
    hex_to_sseg u_hex2  (.hex(dig2),    .dp_in(final_dp_n[2]),  .sseg(hex2_raw));
    hex_to_sseg u_hex1  (.hex(dig1),    .dp_in(final_dp_n[1]),  .sseg(hex1_raw));
    hex_to_sseg u_hex0  (.hex(dig0),    .dp_in(final_dp_n[0]),  .sseg(hex0_raw));

    always_comb
    begin
        hex5_o  =   (!enable_i  ||  blank_i[5])  ?   8'hFF   :   hex5_raw;
        hex4_o  =   (!enable_i  ||  blank_i[4])  ?   8'hFF   :   hex4_raw;
        hex3_o  =   (!enable_i  ||  blank_i[3])  ?   8'hFF   :   hex3_raw;
        hex2_o  =   (!enable_i  ||  blank_i[2])  ?   8'hFF   :   hex2_raw;
        hex1_o  =   (!enable_i  ||  blank_i[1])  ?   8'hFF   :   hex1_raw;
        hex0_o  =   (!enable_i  ||  blank_i[0])  ?   8'hFF   :   hex0_raw;
    end

endmodule