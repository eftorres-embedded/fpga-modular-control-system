module hex_to_sseg(
    input logic [3:0] hex,
    input logic dp_in,
    output logic [7:0] sseg
    );
    
    always_comb
    begin
        case(hex)
            4'h0    :   sseg[6:0] = 7'b1000000;
            4'h1    :   sseg[6:0] = 7'b1111001;
            4'h2    :   sseg[6:0] = 7'b0100100;
            4'h3    :   sseg[6:0] = 7'b0110000;
            4'h4    :   sseg[6:0] = 7'b0011001;
            4'h5    :   sseg[6:0] = 7'b0010010;
            4'h6    :   sseg[6:0] = 7'b0000010;
            4'h7    :   sseg[6:0] = 7'b1111000;
            4'h8    :   sseg[6:0] = 7'b0000000;
            4'h9    :   sseg[6:0] = 7'b0010000;
            4'hA    :   sseg[6:0] = 7'b0001000;
            4'hB    :   sseg[6:0] = 7'b0000011;
            4'hC    :   sseg[6:0] = 7'b1000110;
            4'hD    :   sseg[6:0] = 7'b0100001;
            4'hE    :   sseg[6:0] = 7'b0000110;
            default :   sseg[6:0] = 7'b0001110;
       endcase
       
   end
   
 assign sseg[7]  = dp_in;
endmodule
