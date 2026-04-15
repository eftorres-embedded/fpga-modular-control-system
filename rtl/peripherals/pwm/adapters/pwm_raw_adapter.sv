// pwm_raw_adapter.sv
//
// Raw PWM adapter for the PWM family.
//

module  pwm_raw_adapter(
    input   logic   pwm_i,
    input   logic   invert_i,
    output  logic   pwm_o);

    assign  pwm_o   =   invert_i    ?   ~pwm_i  :   pwm_i;

endmodule