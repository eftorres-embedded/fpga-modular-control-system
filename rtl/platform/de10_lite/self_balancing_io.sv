module self_balancing_io #(
    parameter int GPIO_W                = 36,

    parameter int PIN_BEEPER            = 19,
    parameter int PIN_IR                = 35,
    parameter int PIN_STATUS_LED        = 29,

    parameter int PIN_HALL_A0           = 32,
    parameter int PIN_HALL_A1           = 33,
    parameter int PIN_HALL_B0           = 30,
    parameter int PIN_HALL_B1           = 31,

    parameter int PIN_MPU_SCL       = 20,
    parameter int PIN_MPU_SDA       = 21,

    parameter int PIN_MOTOR_A_PWM       = 22,
    parameter int PIN_MOTOR_A_IN1       = 23,
    parameter int PIN_MOTOR_A_IN2       = 24,

    parameter int PIN_MOTOR_B_IN1       = 25,
    parameter int PIN_MOTOR_B_IN2       = 26,
    parameter int PIN_MOTOR_B_PWM       = 27,

    parameter int PIN_USONIC_ECHO       = 4,
    parameter int PIN_USONIC_TRIG       = 28
) (
    //-------------------------------------------------
    // Physical DE10-Lite GPIO header
    //-------------------------------------------------
    inout  wire [GPIO_W-1:0] GPIO,

    //-------------------------------------------------
    // Auxiliary / non-essential hardware
    //-------------------------------------------------
    input  logic             beeper_i,
    output logic             ir_o,
    input  logic             status_led_i,

    //-------------------------------------------------
    // Hall sensors
    //-------------------------------------------------
    output logic [1:0]       motor_a_hall_o,
    output logic [1:0]       motor_b_hall_o,

    //-------------------------------------------------
    // MPU-6500 I2C interface
    // Open-drain convention:
    //   scl_out = 0 -> pull low
    //   scl_out = 1 -> release
    //
    //   sda_out = 0 -> pull low
    //   sda_out = 1 -> release
    //
    //   master_receiving = 1 -> force SDA released
    //-------------------------------------------------
    input  logic             mpu_scl_out_i,
    input  logic             mpu_sda_out_i,
    input  logic             mpu_master_receiving_i,
    output logic             mpu_scl_in_o,
    output logic             mpu_sda_in_o,

    //-------------------------------------------------
    // TB6612 motor driver
    //-------------------------------------------------
    input  logic             motor_a_pwm_i,
    input  logic             motor_a_in1_i,
    input  logic             motor_a_in2_i,

    input  logic             motor_b_pwm_i,
    input  logic             motor_b_in1_i,
    input  logic             motor_b_in2_i,

    //-------------------------------------------------
    // Ultrasonic sensor
    //-------------------------------------------------
    output logic             usonic_echo_o,
    input  logic             usonic_trig_i
);

    //-------------------------------------------------
    // Auxiliary / non-essential hardware
    //-------------------------------------------------
    assign GPIO[PIN_BEEPER]     = beeper_i;
    assign ir_o                 = GPIO[PIN_IR];
    assign GPIO[PIN_STATUS_LED] = status_led_i;

    //-------------------------------------------------
    // Hall sensors
    //-------------------------------------------------
    assign motor_a_hall_o[0] = GPIO[PIN_HALL_A0];
    assign motor_a_hall_o[1] = GPIO[PIN_HALL_A1];

    assign motor_b_hall_o[0] = GPIO[PIN_HALL_B0];
    assign motor_b_hall_o[1] = GPIO[PIN_HALL_B1];

    //-------------------------------------------------
    // MPU-6500 I2C interface
    // Open-drain: drive low or release
    //-------------------------------------------------
    assign GPIO[PIN_MPU_SCL] = mpu_scl_out_i ? 1'bz : 1'b0;
    assign GPIO[PIN_MPU_SDA] = (mpu_sda_out_i || mpu_master_receiving_i) ? 1'bz : 1'b0;

    assign mpu_scl_in_o = GPIO[PIN_MPU_SCL];
    assign mpu_sda_in_o = GPIO[PIN_MPU_SDA];

    //-------------------------------------------------
    // TB6612 motor driver
    //-------------------------------------------------
    assign GPIO[PIN_MOTOR_A_PWM] = motor_a_pwm_i;
    assign GPIO[PIN_MOTOR_A_IN1] = motor_a_in1_i;
    assign GPIO[PIN_MOTOR_A_IN2] = motor_a_in2_i;

    assign GPIO[PIN_MOTOR_B_PWM] = motor_b_pwm_i;
    assign GPIO[PIN_MOTOR_B_IN1] = motor_b_in1_i;
    assign GPIO[PIN_MOTOR_B_IN2] = motor_b_in2_i;

    //-------------------------------------------------
    // Ultrasonic sensor
    //-------------------------------------------------
    assign usonic_echo_o         = GPIO[PIN_USONIC_ECHO];
    assign GPIO[PIN_USONIC_TRIG] = usonic_trig_i;

endmodule