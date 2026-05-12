module top#(
    parameter int F_CLK_HZ  = 50_000_000,
    parameter int PRECISION = 10,

    parameter bit BUTTON_ACTIVE_LOW = 1'b1,
    parameter bit LINE_ACTIVE_HIGH  = 1'b0,

    parameter bit RIGHT_INVERT = 1'b0,
    parameter bit LEFT_INVERT  = 1'b1,
    
    /*
        The following parametes have been calibrated for our particular build.
        Feel free to modify as you like!
    */

    parameter int DETECT_DISTANCE_MM = 500,

    parameter logic [PRECISION-1:0] SEARCH_SPEED   = 10'd300, 
    parameter logic [PRECISION-1:0] APPROACH_SPEED = 10'd500, 
    parameter logic [PRECISION-1:0] ATTACK_SPEED   = 10'd1023, 
    parameter logic [PRECISION-1:0] TURN_SPEED   = 10'd600, 
    parameter logic [PRECISION-1:0] BACK_SPEED     = 10'd500,
    parameter logic [PRECISION-1:0] BOX_SPEED      = 10'd450,

    parameter int START_DELAY_MS = 5000,

    parameter int ATTACK_NEAR_DISTANCE_MM = 100,

    parameter int DEADTIME_MS   = 1,
    parameter int BACKWARD_MS   = 450,
    parameter int ROTATE_180_MS = 400,
    parameter int TILT_45_MS    = 200

)(
    input  logic        rst_n,
    input  logic        clk,

    input  logic        k1_n,
    input  logic        k2_n,
    input  logic        k3_n,

    output logic        ultrasoindos_T1,
    input  logic        uttrasonidos_R1,
    output logic        ultrasoindos_T2,
    input  logic        uttrasonidos_R2,
    output logic        ultrasoindos_T3,
    input  logic        uttrasonidos_R3,

    input  logic [3:0]  sensores_final_linea,
    output logic        Activate_sensor_final_de_linea,

    output logic [2:0]  motor_derecha,
    output logic [2:0]  motor_izquierda,
    output logic        stby_motores,

    output logic        dp_out,
    output logic [3:0]  disp_sel,
    output logic [6:0]  segment_val,

    output logic        bell,

    output logic [2:0]  modo_led,

    output logic [2:0]  debug_fsm_state,
    output logic [2:0]  debug_cmd,
    output logic [2:0]  debug_cmd_applied,
    output logic [2:0]  debug_detect,
    output logic        debug_motor_enable,
    output logic        debug_line,
    output logic        debug_deadtime,
    output logic        debug_brake
);

    top_displayless #(
        .F_CLK_HZ(F_CLK_HZ),
        .PRECISION(PRECISION),
        .BUTTON_ACTIVE_LOW(BUTTON_ACTIVE_LOW),
        .LINE_ACTIVE_HIGH(LINE_ACTIVE_HIGH),
        .DETECT_DISTANCE_MM(DETECT_DISTANCE_MM),
        .SEARCH_SPEED(SEARCH_SPEED),
        .APPROACH_SPEED(APPROACH_SPEED),
        .ATTACK_SPEED(ATTACK_SPEED),
        .TURN_SPEED(TURN_SPEED),
        .BACK_SPEED(BACK_SPEED),
        .BOX_SPEED(BOX_SPEED),
        .START_DELAY_MS(START_DELAY_MS),
        .ATTACK_NEAR_DISTANCE_MM(ATTACK_NEAR_DISTANCE_MM),
        .DEADTIME_MS(DEADTIME_MS),
        .BACKWARD_MS(BACKWARD_MS),
        .ROTATE_180_MS(ROTATE_180_MS),
        .TILT_45_MS(TILT_45_MS),
        .RIGHT_INVERT(RIGHT_INVERT),
        .LEFT_INVERT(LEFT_INVERT)
    ) robot_i (
        .rst_n(rst_n),
        .clk(clk),

        .ultrasoindos_T1(ultrasoindos_T1),
        .uttrasonidos_R1(uttrasonidos_R1),
        .ultrasoindos_T2(ultrasoindos_T2),
        .uttrasonidos_R2(uttrasonidos_R2),
        .ultrasoindos_T3(ultrasoindos_T3),
        .uttrasonidos_R3(uttrasonidos_R3),

        .sensores_final_linea(sensores_final_linea),
        .Activate_sensor_final_de_linea(Activate_sensor_final_de_linea),

        .motor_derecha(motor_derecha),
        .motor_izquierda(motor_izquierda),
        .stby_motores(stby_motores),

        .boton_start_driver(k3_n),
        .boton_box_tighten(k1_n),
        .boton_box_loosen(k2_n),

        .dp_out(dp_out),
        .disp_sel(disp_sel),
        .segment_val(segment_val),

        .bell(bell),

        .debug_fsm_state(debug_fsm_state),
        .debug_cmd(debug_cmd),
        .debug_cmd_applied(debug_cmd_applied),
        .debug_detect(debug_detect),
        .debug_motor_enable(debug_motor_enable),
        .debug_line(debug_line),
        .debug_deadtime(debug_deadtime),
        .debug_brake(debug_brake)
    );

    // modo_led[2] = left, mode_led[1] = center, mode_led[0] = right.
    assign modo_led = debug_detect;
endmodule
