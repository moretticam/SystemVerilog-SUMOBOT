// Output convention to TB6612:
//   motor_derecha[2]   = PWMA
//   motor_derecha[1]   = AIN1
//   motor_derecha[0]   = AIN2
//   motor_izquierda[2] = PWMB
//   motor_izquierda[1] = BIN1
//   motor_izquierda[0] = BIN2
//   stby_motores       = STBY
//
// Compatible commands with top_fsm:
//   0 = STOP / S_WAITBTN
//   1 = IDLE / S_IDLE
//   2 = FORWARD
//   3 = BACKWARD
//   4 = ROTATE
//   5 = TILTR / RIGHT
//   6 = TILTL / LEFT
//   7 = BRAKE activo

module driver_tb6612 #(
    parameter int PRECISION    = 10,
    parameter int F_CLK_HZ     = 50_000_000,
    parameter int DEADTIME_MS  = 120,
    parameter bit RIGHT_INVERT = 1'b0,
    parameter bit LEFT_INVERT  = 1'b0
)(
    input  logic                 rst_n,
    input  logic                 clk,

    input  logic                 enable,

    input  logic [2:0]           cmd,
    input  logic [PRECISION-1:0] speed,

    output logic [2:0]           motor_derecha,
    output logic [2:0]           motor_izquierda,
    output logic                 stby_motores,

    // optional debugging
    output logic [2:0]           debug_cmd_requested,
    output logic [2:0]           debug_cmd_applied,
    output logic                 debug_deadtime,
    output logic                 debug_brake
);

    localparam logic [2:0] CMD_STOP     = 3'd0;
    localparam logic [2:0] CMD_IDLE     = 3'd1;
    localparam logic [2:0] CMD_FORWARD  = 3'd2;
    localparam logic [2:0] CMD_BACKWARD = 3'd3;
    localparam logic [2:0] CMD_ROTATE   = 3'd4;
    localparam logic [2:0] CMD_TILTR    = 3'd5;
    localparam logic [2:0] CMD_TILTL    = 3'd6;
    localparam logic [2:0] CMD_BRAKE    = 3'd7;

    localparam int DEADTIME_TICKS = (F_CLK_HZ / 1000) * DEADTIME_MS;
    localparam int DEAD_W = (DEADTIME_TICKS <= 1) ? 1 : $clog2(DEADTIME_TICKS + 1);

    logic enable_d;
    logic [2:0] requested_cmd_d;
    logic [2:0] target_cmd;
    logic [2:0] applied_cmd;
    logic [DEAD_W-1:0] dead_cnt;
    logic in_deadtime;

    logic [PRECISION-1:0] power_valueA;
    logic [PRECISION-1:0] power_valueB;
    logic in1A, in2A, in1B, in2B;
    logic pwm_outA, pwm_outB;

    assign stby_motores = enable;

    assign motor_derecha[2]   = pwm_outA;
    assign motor_derecha[1]   = in1A;
    assign motor_derecha[0]   = in2A;

    assign motor_izquierda[2] = pwm_outB;
    assign motor_izquierda[1] = in1B;
    assign motor_izquierda[0] = in2B;

    assign debug_cmd_requested = cmd;
    assign debug_cmd_applied   = applied_cmd;
    assign debug_deadtime      = in_deadtime;
    assign debug_brake         = enable && (applied_cmd == CMD_BRAKE);

    pwm #(
        .PRECISION(PRECISION),
        .F_CLK_HZ(F_CLK_HZ)
    ) pwmA (
        .rst_n(rst_n),
        .clk(clk),
        .power_value(power_valueA),
        .pwm_out(pwm_outA)
    );

    pwm #(
        .PRECISION(PRECISION),
        .F_CLK_HZ(F_CLK_HZ)
    ) pwmB (
        .rst_n(rst_n),
        .clk(clk),
        .power_value(power_valueB),
        .pwm_out(pwm_outB)
    );

    function automatic logic is_stop_like(input logic [2:0] c);
        begin
            is_stop_like = (c == CMD_STOP) || (c == CMD_IDLE);
        end
    endfunction

    function automatic logic is_brake(input logic [2:0] c);
        begin
            is_brake = (c == CMD_BRAKE);
        end
    endfunction
	 
	 /*
		Transition deadtiming:
			- STOP/IDLE: Immediatly
			- BRAKE: Immediatly, wo previous deadtime
			- Movement: Applies deadtime before next move
	 */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_d        <= 1'b0;
            requested_cmd_d <= CMD_STOP;
            target_cmd      <= CMD_STOP;
            applied_cmd     <= CMD_STOP;
            dead_cnt        <= '0;
            in_deadtime     <= 1'b0;
        end else begin
            enable_d <= enable;

            if (!enable) begin
                requested_cmd_d <= CMD_STOP;
                target_cmd      <= CMD_STOP;
                applied_cmd     <= CMD_STOP;
                dead_cnt        <= '0;
                in_deadtime     <= 1'b0;
            end else begin
                if ((cmd != requested_cmd_d) || !enable_d) begin
                    requested_cmd_d <= cmd;
                    target_cmd      <= cmd;

                    if (is_stop_like(cmd)) begin
                        applied_cmd <= CMD_STOP;
                        dead_cnt    <= '0;
                        in_deadtime <= 1'b0;
                    end else if (is_brake(cmd)) begin
                        applied_cmd <= CMD_BRAKE;
                        dead_cnt    <= '0;
                        in_deadtime <= 1'b0;
                    end else begin
                        if (DEADTIME_MS == 0) begin
                            applied_cmd <= cmd;
                            dead_cnt    <= '0;
                            in_deadtime <= 1'b0;
                        end else begin
                            applied_cmd <= CMD_STOP;
                            dead_cnt    <= DEADTIME_TICKS[DEAD_W-1:0];
                            in_deadtime <= 1'b1;
                        end
                    end
                end else if (in_deadtime) begin
                    applied_cmd <= CMD_STOP;

                    if (dead_cnt == 0) begin
                        applied_cmd <= target_cmd;
                        in_deadtime <= 1'b0;
                    end else begin
                        dead_cnt <= dead_cnt - 1'b1;
                    end
                end
            end
        end
    end

    // Command translation to TB6612 inputs
    always_comb begin
        power_valueA = '0;
        power_valueB = '0;
        in1A = 1'b0;
        in2A = 1'b0;
        in1B = 1'b0;
        in2B = 1'b0;

        if (enable) begin
            case (applied_cmd)
                CMD_FORWARD: begin
                    power_valueA = speed;
                    power_valueB = speed;

                    if (!RIGHT_INVERT) begin in1A = 1'b1; in2A = 1'b0; end
                    else               begin in1A = 1'b0; in2A = 1'b1; end

                    if (!LEFT_INVERT)  begin in1B = 1'b1; in2B = 1'b0; end
                    else               begin in1B = 1'b0; in2B = 1'b1; end
                end

                CMD_BACKWARD: begin
                    power_valueA = speed;
                    power_valueB = speed;

                    if (!RIGHT_INVERT) begin in1A = 1'b0; in2A = 1'b1; end
                    else               begin in1A = 1'b1; in2A = 1'b0; end

                    if (!LEFT_INVERT)  begin in1B = 1'b0; in2B = 1'b1; end
                    else               begin in1B = 1'b1; in2B = 1'b0; end
                end

                CMD_ROTATE,
                CMD_TILTR: begin
                    power_valueA = speed;
                    power_valueB = speed;

                    if (!RIGHT_INVERT) begin in1A = 1'b0; in2A = 1'b1; end
                    else               begin in1A = 1'b1; in2A = 1'b0; end

                    if (!LEFT_INVERT)  begin in1B = 1'b1; in2B = 1'b0; end
                    else               begin in1B = 1'b0; in2B = 1'b1; end
                end

                CMD_TILTL: begin
                    power_valueA = speed;
                    power_valueB = speed;

                    if (!RIGHT_INVERT) begin in1A = 1'b1; in2A = 1'b0; end
                    else               begin in1A = 1'b0; in2A = 1'b1; end

                    if (!LEFT_INVERT)  begin in1B = 1'b0; in2B = 1'b1; end
                    else               begin in1B = 1'b1; in2B = 1'b0; end
                end

                CMD_BRAKE: begin
                    power_valueA = {PRECISION{1'b1}};
                    power_valueB = {PRECISION{1'b1}};
                    in1A = 1'b1;
                    in2A = 1'b1;
                    in1B = 1'b1;
                    in2B = 1'b1;
                end

                default: begin
                    power_valueA = '0;
                    power_valueB = '0;
                    in1A = 1'b0;
                    in2A = 1'b0;
                    in1B = 1'b0;
                    in2B = 1'b0;
                end
            endcase
        end
    end

endmodule
