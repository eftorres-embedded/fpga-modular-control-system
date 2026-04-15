module self_balancing_io #(
    parameter int GPIO_W               = 36,

    parameter int PIN_BEEPER           = 19,
    parameter int PIN_IR               = 35,
    parameter int PIN_STATUS_LED       = 29,

    parameter int PIN_HALL_A0           = 32,
    parameter int PIN_HALL_A1           = 33,
    parameter int PIN_HALL_B0           = 30,
    parameter int PIN_HALL_B1           = 31,

    parameter int PIN_MPU_I2C_SCL      = 20,
    parameter int PIN_MPU_I2C_SDA      = 21,

    parameter int PIN_MOTOR_A_PWM      = 22,
    parameter int PIN_MOTOR_A_IN1      = 23,
    parameter int PIN_MOTOR_A_IN2      = 24,

    parameter int PIN_MOTOR_B_IN1      = 25,
    parameter int PIN_MOTOR_B_IN2      = 26,
    parameter int PIN_MOTOR_B_PWM      = 27,

    parameter int PIN_USONIC_ECHO      = 4,
    parameter int PIN_USONIC_TRIG      = 28
) (
    //-------------------------------------------------
    // Physical DE10-Lite GPIO header
    //-------------------------------------------------
    inout  wire [GPIO_W-1:0] GPIO,

    //-------------------------------------------------
    // Auxiliary / non-essential hardware
    //-------------------------------------------------
    input  logic             beeper_o,
    output wire              ir_i,
    input  logic             status_led_o,

    //-------------------------------------------------
    // Quadrature encoders
    // Bit ordering:
    //-------------------------------------------------
    output wire [1:0]        motor_a_hall_i,
    output wire [1:0]        motor_b_hall_i,

    //-------------------------------------------------
    // MPU-6500 I2C interface
    // Open-drain convention:
    //   *_oe = 1 -> pull line low
    //   *_oe = 0 -> release line (Z)
    //-------------------------------------------------
    input  logic             mpu_i2c_scl_drive_low,
    output wire              mpu_i2c_scl_i,
    input  logic             mpu_i2c_sda_drive_low,
    output wire              mpu_i2c_sda_i,

    //-------------------------------------------------
    // TB6612 motor driver
    //-------------------------------------------------
    input  logic             motor_a_pwm_o,
    input  logic             motor_a_in1_o,
    input  logic             motor_a_in2_o,

    input  logic             motor_b_pwm_o,
    input  logic             motor_b_in1_o,
    input  logic             motor_b_in2_o,

    //-------------------------------------------------
    // Ultrasonic sensor
    //-------------------------------------------------
    output wire              usonic_echo_i,
    input  logic             usonic_trig_o
);

    //-------------------------------------------------
    // Auxiliary / non-essential hardware
    //-------------------------------------------------
    assign GPIO[PIN_BEEPER]     = beeper_o;
    assign ir_i                 = GPIO[PIN_IR];
    assign GPIO[PIN_STATUS_LED] = status_led_o;

    //-------------------------------------------------
    // Quadrature encoders
    //-------------------------------------------------
    assign motor_a_hall_i[0] = GPIO[PIN_HALL_A0];
    assign motor_a_hall_i[1] = GPIO[PIN_HALL_A1];

    assign motor_b_hall_i[0] = GPIO[PIN_HALL_B0];
    assign motor_b_hall_i[1] = GPIO[PIN_HALL_B1];

    //-------------------------------------------------
    // MPU-6500 I2C interface
    // Open-drain: drive low or release
    //-------------------------------------------------
    assign GPIO[PIN_MPU_I2C_SCL] = mpu_i2c_scl_drive_low ? 1'b0 : 1'bz;
    assign GPIO[PIN_MPU_I2C_SDA] = mpu_i2c_sda_drive_low ? 1'b0 : 1'bz;

    assign mpu_i2c_scl_i = GPIO[PIN_MPU_I2C_SCL];
    assign mpu_i2c_sda_i = GPIO[PIN_MPU_I2C_SDA];

    //-------------------------------------------------
    // TB6612 motor driver
    //-------------------------------------------------
    assign GPIO[PIN_MOTOR_A_PWM] = motor_a_pwm_o;
    assign GPIO[PIN_MOTOR_A_IN1] = motor_a_in1_o;
    assign GPIO[PIN_MOTOR_A_IN2] = motor_a_in2_o;

    assign GPIO[PIN_MOTOR_B_PWM] = motor_b_pwm_o;
    assign GPIO[PIN_MOTOR_B_IN1] = motor_b_in1_o;
    assign GPIO[PIN_MOTOR_B_IN2] = motor_b_in2_o;

    //-------------------------------------------------
    // Ultrasonic sensor
    //-------------------------------------------------
    assign usonic_echo_i         = GPIO[PIN_USONIC_ECHO];
    assign GPIO[PIN_USONIC_TRIG] = usonic_trig_o;

endmodule