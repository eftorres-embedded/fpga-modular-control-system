`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/08/2025 09:18:15 PM
// Design Name: 
// Module Name: seven_seg_mux
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module seven_seg_mux(
    input logic clock,
    input logic nrst,
    input logic [7:0] in_digit0,
    input logic [7:0] in_digit1,
    input logic [7:0] in_digit2,
    input logic[7:0] in_digit3,
    output logic [7:0] out_ssegment,
    output logic [4:0] an
    );
   
    enum 
    always_ff @(posedge clock, negedge nrst)
    begin
        if(!nrst)
        begin
            out_ssegment <= in_digit0;
        end
        else
            
           
    
    
    
    
    end
endmodule
