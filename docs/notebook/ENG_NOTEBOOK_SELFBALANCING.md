 
                         +------------------+
brake ------------------>| highest priority |-------------------+
                         +------------------+                   |
                                                                v
                         +------------------+            +-------------+
coast ------------------>| next priority    |----------->| output      |
                         +------------------+            | select/mux  |----> PWM_out
                                                         |             |----> in1
direction ---------------------------------------------->|             |----> in2
                                                         +-------------+
                                                               ^
                                                               |
pwm_in --------------------------------------------------------+




MMIO -> pwm_regs -> active duty + motor control -> pwm_core_ip -> pwm_raw[i]
                                                      |
                                                      v
                                            hbridge_cmd_encoder[i]
                                                      |
                                                      +-> pwm_o
                                                      +-> in1_o
                                                      +-> in2_o