/*
	Integrated top without display
*/

module top_displayless #(
    parameter int F_CLK_HZ  = 50_000_000,
    parameter int PRECISION = 10,

    parameter bit BUTTON_ACTIVE_LOW = 1'b1,
    parameter bit LINE_ACTIVE_HIGH  = 1'b1,

    parameter int DETECT_DISTANCE_MM = 500,

    parameter logic [PRECISION-1:0] SEARCH_SPEED   = 10'd350,
    parameter logic [PRECISION-1:0] APPROACH_SPEED = 10'd600,
    parameter logic [PRECISION-1:0] ATTACK_SPEED   = 10'd850,
    parameter logic [PRECISION-1:0] TURN_SPEED     = 10'd600,
    parameter logic [PRECISION-1:0] BACK_SPEED     = 10'd650,

    // "Boxes" speed when screwing/unscrewin tires
    parameter logic [PRECISION-1:0] BOX_SPEED      = 10'd450,

    // Last-minute add-on: delay after START button is pressed before starting FSM
    parameter int START_DELAY_MS = 5000,

    parameter int ATTACK_NEAR_DISTANCE_MM = 250,

    parameter int DEADTIME_MS   = 120,
    parameter int BACKWARD_MS   = 450,
    parameter int ROTATE_180_MS = 500,
    parameter int TILT_45_MS    = 140,

    parameter bit RIGHT_INVERT = 1'b0,
    parameter bit LEFT_INVERT  = 1'b0
)(
    input  logic        rst_n,
    input  logic        clk,

    //Ultrasounds	
    output logic        ultrasoindos_T1,
    input  logic        uttrasonidos_R1,
    output logic        ultrasoindos_T2,
    input  logic        uttrasonidos_R2,
    output logic        ultrasoindos_T3,
    input  logic        uttrasonidos_R3,

    // Line sensors
    input  logic [3:0]  sensores_final_linea,
    output logic        Activate_sensor_final_de_linea,

    // TB6612 driver
    output logic [2:0]  motor_derecha,
    output logic [2:0]  motor_izquierda,
    output logic        stby_motores,

    /* Buttons
			boton_start_driver -> K3: start FSM + enable driver
			boton_box_tighten  -> K1: boxes screw while pressed
			boton_box_loosen   -> K2: boxes unscrew while pressed
	 */
    input  logic        boton_start_driver,
    input  logic        boton_box_tighten,
    input  logic        boton_box_loosen,

    // Unused display
    output logic        dp_out,
    output logic [3:0]  disp_sel,
    output logic [6:0]  segment_val,

    output logic        bell,

    // Optional debug LEDs
    output logic [2:0]  debug_fsm_state,
    output logic [2:0]  debug_cmd,
    output logic [2:0]  debug_cmd_applied,
    output logic [2:0]  debug_detect,
    output logic        debug_motor_enable,
    output logic        debug_line,
    output logic        debug_deadtime,
    output logic        debug_brake
);

    logic start_pulse;
    logic box_tighten_pressed;
    logic box_loosen_pressed;
    logic motor_enable;
    logic start_delay_active;
    logic start_delayed_pulse;

	 /*
		Last-minute add-on: Robust delay, counts ms instead of cycles.
		DIDN'T WORK, REVIEW
	*/
    localparam int CLK_PER_MS = (F_CLK_HZ + 999) / 1000;
    localparam int START_DELAY_MS_SAFE = (START_DELAY_MS <= 0) ? 1 : START_DELAY_MS;
    localparam int CLK_MS_W = (CLK_PER_MS <= 1) ? 1 : $clog2(CLK_PER_MS);
    localparam int DELAY_MS_W = (START_DELAY_MS_SAFE <= 1) ? 1 : $clog2(START_DELAY_MS_SAFE + 1);

    logic [CLK_MS_W-1:0] delay_clk_cnt;
    logic [DELAY_MS_W-1:0] delay_ms_cnt;

    logic box_mode;
    logic [2:0] cmd_to_driver;
    logic [PRECISION-1:0] speed_to_driver;
    logic driver_enable;

    logic line_detected;

    logic us_left;
    logic us_center;
    logic us_right;

    logic [11:0] distance_left;
    logic [11:0] distance_center;
    logic [11:0] distance_right;

    logic [2:0] cmd;
    logic [PRECISION-1:0] speed;

    assign bell = 1'b1;
    assign Activate_sensor_final_de_linea = 1'b1;

    assign line_detected = LINE_ACTIVE_HIGH ? (|sensores_final_linea) : (~&sensores_final_linea);

    assign debug_cmd          = cmd;
    assign debug_detect       = {us_left, us_center, us_right};
    assign debug_motor_enable = driver_enable;
    assign debug_line         = line_detected;

    button #(
        .F_CLK_HZ(F_CLK_HZ),
        .DEBOUNCE_MS(30),
        .ACTIVE_LOW(BUTTON_ACTIVE_LOW)
    ) start_button_i (
        .clk(clk),
        .rst_n(rst_n),
        .btn_in(boton_start_driver),
        .btn_pressed(),
        .btn_pulse(start_pulse)
    );

    button #(
        .F_CLK_HZ(F_CLK_HZ),
        .DEBOUNCE_MS(30),
        .ACTIVE_LOW(BUTTON_ACTIVE_LOW)
    ) box_tighten_button_i (
        .clk(clk),
        .rst_n(rst_n),
        .btn_in(boton_box_tighten),
        .btn_pressed(box_tighten_pressed),
        .btn_pulse()
    );

    button #(
        .F_CLK_HZ(F_CLK_HZ),
        .DEBOUNCE_MS(30),
        .ACTIVE_LOW(BUTTON_ACTIVE_LOW)
    ) box_loosen_button_i (
        .clk(clk),
        .rst_n(rst_n),
        .btn_in(boton_box_loosen),
        .btn_pressed(box_loosen_pressed),
        .btn_pulse()
    );
	
	 /*
		FAULTY -> REVIEW NEEDED
		
		K3 starts START_DELAY_MS delay
	 */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            motor_enable        <= 1'b0;
            start_delay_active  <= 1'b0;
            delay_clk_cnt       <= '0;
            delay_ms_cnt        <= '0;
            start_delayed_pulse <= 1'b0;
        end else begin
            start_delayed_pulse <= 1'b0;

            if (start_pulse && !motor_enable && !start_delay_active) begin
                start_delay_active <= 1'b1;
                delay_clk_cnt      <= '0;
                delay_ms_cnt       <= '0;
            end else if (start_delay_active) begin
                if (delay_clk_cnt == CLK_PER_MS - 1) begin
                    delay_clk_cnt <= '0;

                    if (delay_ms_cnt == START_DELAY_MS_SAFE - 1) begin
                        start_delay_active  <= 1'b0;
                        delay_ms_cnt        <= '0;
                        motor_enable        <= 1'b1;
                        start_delayed_pulse <= 1'b1;
                    end else begin
                        delay_ms_cnt <= delay_ms_cnt + 1'b1;
                    end
                end else begin
                    delay_clk_cnt <= delay_clk_cnt + 1'b1;
                end
            end
        end
    end

    assign box_mode = box_tighten_pressed ^ box_loosen_pressed;

    always_comb begin
        cmd_to_driver   = cmd;
        speed_to_driver = speed;
        driver_enable   = motor_enable;

        if (box_mode) begin
            driver_enable   = 1'b1;
            speed_to_driver = BOX_SPEED;
            if (box_tighten_pressed) begin
                cmd_to_driver = 3'd2; // CMD_FORWARD
            end else begin
                cmd_to_driver = 3'd3; // CMD_BACKWARD
            end
        end
    end

    ultrasonic_3x_manager #(
        .F_CLK_HZ(F_CLK_HZ),
        .STARTUP_DELAY_MS(100),
        .DELAY_AFTER_MEASURE_MS(30),
        .SENSOR_TIMEOUT_MS(35),
        .DETECT_DISTANCE_MM(DETECT_DISTANCE_MM),
        .MIN_VALID_DISTANCE_MM(20),
        .TIMEOUT_DISTANCE_MM(4030)
    ) ultrasonic_manager_i (
        .clk(clk),
        .rst_n(rst_n),
        .enable(1'b1),
		  
		  /*
				Assumed config:
					T/R1 = left
					T/R2 = center
					T/R3 = right
		  */
        .echo_left(uttrasonidos_R1),
        .echo_center(uttrasonidos_R2),
        .echo_right(uttrasonidos_R3),
        .trig_left(ultrasoindos_T1),
        .trig_center(ultrasoindos_T2),
        .trig_right(ultrasoindos_T3),

        .detect_left(us_left),
        .detect_center(us_center),
        .detect_right(us_right),

        .distance_left(distance_left),
        .distance_center(distance_center),
        .distance_right(distance_right),

        .debug_sensor_active(),
        .debug_new_sample()
    );

    fsm #(
        .F_CLK_HZ(F_CLK_HZ),
        .PRECISION(PRECISION),
        .SEARCH_SPEED(SEARCH_SPEED),
        .APPROACH_SPEED(APPROACH_SPEED),
        .ATTACK_SPEED(ATTACK_SPEED),
        .TURN_SPEED(TURN_SPEED),
        .BACK_SPEED(BACK_SPEED),
        .ATTACK_NEAR_DISTANCE_MM(ATTACK_NEAR_DISTANCE_MM),
        .BRAKE_LINE_MS(80),
        .BACKWARD_MS(BACKWARD_MS),
        .ROTATE_180_MS(ROTATE_180_MS),
        .TILT_45_MS(TILT_45_MS)
    ) fsm_i (
        .clk(clk),
        .rst_n(rst_n),
        .line(line_detected),
        .button_start(start_delayed_pulse),
        .us_center(us_center),
        .us_right(us_right),
        .us_left(us_left),
        .distance_center(distance_center),
        .distance_left(distance_left),
        .distance_right(distance_right),
        .cmd(cmd),
        .speed(speed),
        .debug_state(debug_fsm_state)
    );

    driver_tb6612 #(
        .PRECISION(PRECISION),
        .F_CLK_HZ(F_CLK_HZ),
        .DEADTIME_MS(DEADTIME_MS),
        .RIGHT_INVERT(RIGHT_INVERT),
        .LEFT_INVERT(LEFT_INVERT)
    ) driver_i (
        .rst_n(rst_n),
        .clk(clk),
        .enable(driver_enable),
        .cmd(cmd_to_driver),
        .speed(speed_to_driver),
        .motor_derecha(motor_derecha),
        .motor_izquierda(motor_izquierda),
        .stby_motores(stby_motores),
        .debug_cmd_requested(),
        .debug_cmd_applied(debug_cmd_applied),
        .debug_deadtime(debug_deadtime),
        .debug_brake(debug_brake)
    );

    // Disabled display
    assign dp_out      = 1'b1;
    assign disp_sel    = 4'b1111;
    assign segment_val = 7'b1111111;

endmodule

/*
	Button with debouncer. The whole idea is to use this as a generic button primitive.
	We declare two outputs for that purpose, pressed (used by "Boxes") and pulse (used to start).
	2-FF synchronizer to avoid metastability.
*/

module button #(
    parameter int F_CLK_HZ    = 50_000_000,
    parameter int DEBOUNCE_MS = 30,
    parameter bit ACTIVE_LOW  = 1'b1
)(
    input  logic clk,
    input  logic rst_n,
    input  logic btn_in,
    output logic btn_pressed,
    output logic btn_pulse
);

    localparam int DEBOUNCE_TICKS = (F_CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam int CNT_W = (DEBOUNCE_TICKS <= 1) ? 1 : $clog2(DEBOUNCE_TICKS + 1);

    logic btn_sync_0;
    logic btn_sync_1;
    logic btn_raw_pressed;
    logic debounced;
    logic debounced_d;
    logic [CNT_W-1:0] cnt;

    assign btn_raw_pressed = ACTIVE_LOW ? ~btn_sync_1 : btn_sync_1;
    assign btn_pressed     = debounced;
    assign btn_pulse       = debounced && !debounced_d; // ! To ensure it fires on rising edge and not on button release

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_sync_0  <= ACTIVE_LOW ? 1'b1 : 1'b0;
            btn_sync_1  <= ACTIVE_LOW ? 1'b1 : 1'b0;
            debounced   <= 1'b0;
            debounced_d <= 1'b0;
            cnt         <= '0;
        end else begin
            btn_sync_0  <= btn_in;
            btn_sync_1  <= btn_sync_0;
            debounced_d <= debounced;

            if (btn_raw_pressed == debounced) begin
                cnt <= '0;
            end else begin
                if (cnt >= DEBOUNCE_TICKS - 1) begin
                    debounced <= btn_raw_pressed;	// We ONLY update the state of the button once cnt has been saturated
                    cnt       <= '0;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

endmodule
