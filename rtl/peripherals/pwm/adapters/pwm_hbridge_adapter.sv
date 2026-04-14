// pwm_hbridge_adapter.sv
//
// Per-channel H-bridge output adapter for PWM motor flavor.
//
// -----------------------------------------------------------------------------
// Design intent
// -----------------------------------------------------------------------------
// This is a small combinational adapter that converts:
//
//   - direction
//   - brake
//   - coast
//   - raw PWM
//
// into H-bridge control outputs:
//
//   - pwm_o
//   - in1_o
//   - in2_o
//
// Priority:
//   brake > coast > normal PWM drive
//
// Normal mode:
//   direction_i = 1 -> in1=1, in2=0
//   direction_i = 0 -> in1=0, in2=1
//   pwm_o follows pwm_i
//
// Coast mode:
//   pwm_o = 1
//   in1_o = 0
//   in2_o = 0
//
// Brake mode:
//   pwm_o = 1
//   in1_o = 1
//   in2_o = 1
//

module pwm_hbridge_adapter (
    input   logic   direction_i,
    input   logic   brake_i,
    input   logic   coast_i,
    input   logic   pwm_i,

    output  logic   pwm_o,
    output  logic   in1_o,
    output  logic   in2_o);

    always_comb
    begin
        // Default: normal directional PWM mode
        pwm_o = pwm_i;
        in1_o = direction_i;
        in2_o = ~direction_i;

        // Priority override:
        // brake > coast > normal PWM
        if(brake_i)
        begin
            pwm_o = 1'b1;
            in1_o = 1'b1;
            in2_o = 1'b1;
        end
        else if(coast_i)
        begin
            pwm_o = 1'b1;
            in1_o = 1'b0;
            in2_o = 1'b0;
        end
    end

endmodule