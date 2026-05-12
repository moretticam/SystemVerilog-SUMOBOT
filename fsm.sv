// Line detection sequence:
//   LINE -> BRAKE_LINE -> BACKWARD -> ROTATE -> IDLE

module fsm #(
    parameter int F_CLK_HZ  = 50_000_000,
    parameter int PRECISION = 10,

    parameter logic [PRECISION-1:0] SEARCH_SPEED   = 10'd350,
    parameter logic [PRECISION-1:0] APPROACH_SPEED = 10'd600,
    parameter logic [PRECISION-1:0] ATTACK_SPEED   = 10'd850,
    parameter logic [PRECISION-1:0] TURN_SPEED     = 10'd600,
    parameter logic [PRECISION-1:0] BACK_SPEED     = 10'd850,
	 
	 /*
		If opponent is detected but distance > than ATTACK_NEAR_DISTANCE_M, --> APPROACH_SPEED.
		This ensures that in most cases we won't get out of the ring when following the opponent around
	 */
    parameter int ATTACK_NEAR_DISTANCE_MM = 250,

    parameter int BRAKE_LINE_MS = 80,
    parameter int BACKWARD_MS   = 500,
    parameter int ROTATE_180_MS = 750,
    parameter int TILT_45_MS    = 250
)(
    input  logic                 clk,
    input  logic                 rst_n,

    input  logic                 line,
    input  logic                 button_start,

    input  logic                 us_center,
    input  logic                 us_right,
    input  logic                 us_left,
    input  logic [11:0]          distance_center,
    input  logic [11:0]          distance_left,
    input  logic [11:0]          distance_right,

    output logic [2:0]           cmd,
    output logic [PRECISION-1:0] speed,
    output logic [2:0]           debug_state
);

    localparam logic [2:0] CMD_STOP     = 3'd0;
    localparam logic [2:0] CMD_IDLE     = 3'd1;
    localparam logic [2:0] CMD_FORWARD  = 3'd2;
    localparam logic [2:0] CMD_BACKWARD = 3'd3;
    localparam logic [2:0] CMD_ROTATE   = 3'd4;
    localparam logic [2:0] CMD_TILTR    = 3'd5;
    localparam logic [2:0] CMD_TILTL    = 3'd6;
    localparam logic [2:0] CMD_BRAKE    = 3'd7;

    typedef enum logic [3:0] {
        S_WAITBTN    = 4'd0,
        S_IDLE       = 4'd1,
        S_FORWARD    = 4'd2,
        S_BACKWARD   = 4'd3,
        S_ROTATE     = 4'd4,
        S_TILTR      = 4'd5,
        S_TILTL      = 4'd6,
        S_BRAKE_LINE = 4'd7,
        NUEVO_WAIT	 = 4'd8
    } state_t;

    state_t state;
    
    

    localparam int BRAKE_LINE_TICKS = (F_CLK_HZ / 1000) * BRAKE_LINE_MS;
    localparam int BACKWARD_TICKS   = (F_CLK_HZ / 1000) * BACKWARD_MS;
    localparam int ROTATE_180_TICKS = (F_CLK_HZ / 1000) * ROTATE_180_MS;
    localparam int TILT_45_TICKS    = (F_CLK_HZ / 1000) * TILT_45_MS;

    localparam int MAX_1 = (BRAKE_LINE_TICKS > BACKWARD_TICKS) ?
                           BRAKE_LINE_TICKS : BACKWARD_TICKS;

    localparam int MAX_2 = (ROTATE_180_TICKS > TILT_45_TICKS) ?
                           ROTATE_180_TICKS : TILT_45_TICKS;

    localparam int MAX_TIMER_TICKS = (MAX_1 > MAX_2) ? MAX_1 : MAX_2;

    localparam int TIMER_W = (MAX_TIMER_TICKS <= 1) ? 1 : $clog2(MAX_TIMER_TICKS + 1);

    logic [TIMER_W-1:0] timer;

    logic [PRECISION-1:0] center_attack_speed;
    localparam logic [11:0] ATTACK_NEAR_DISTANCE_MM_C = ATTACK_NEAR_DISTANCE_MM[11:0];

    always_comb begin
        if (distance_center <= ATTACK_NEAR_DISTANCE_MM_C) begin
            center_attack_speed = ATTACK_SPEED;
        end else begin
            center_attack_speed = APPROACH_SPEED;
        end
    end

	 
	 /*
			Last-minute add-on: If multiple sensors are detected, choose the minimum distance one
			BUG-PATCH: If lateral sensors detect at the same time and distance is tied, go back to search mode.
	 */
	 
    logic nearest_center;
    logic nearest_left;
    logic nearest_right;
    logic both_sides_without_center_equal;

    always_comb begin
        nearest_center = 1'b0;
        nearest_left   = 1'b0;
        nearest_right  = 1'b0;

        if (us_center && (!us_left  || (distance_center <= distance_left)) &&
                         (!us_right || (distance_center <= distance_right))) begin
            nearest_center = 1'b1;
        end else if (us_left && (!us_right || (distance_left <= distance_right))) begin
            nearest_left = 1'b1;
        end else if (us_right) begin
            nearest_right = 1'b1;
        end
    end

    assign both_sides_without_center_equal = us_left && us_right && !us_center &&
                                             (distance_left == distance_right);

    localparam logic [TIMER_W-1:0] BRAKE_LINE_TICKS_C = BRAKE_LINE_TICKS[TIMER_W-1:0];
    localparam logic [TIMER_W-1:0] BACKWARD_TICKS_C   = BACKWARD_TICKS[TIMER_W-1:0];
    localparam logic [TIMER_W-1:0] ROTATE_180_TICKS_C = ROTATE_180_TICKS[TIMER_W-1:0];
    localparam logic [TIMER_W-1:0] TILT_45_TICKS_C    = TILT_45_TICKS[TIMER_W-1:0];

    assign debug_state = state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_WAITBTN;
            timer <= '0;
            cmd   <= CMD_STOP;
            speed <= '0;
        end else begin

            /*
					Prioritize line detection, but don't interrupt an ongoing escape maneuver
				*/
            if (line &&
                (state != S_WAITBTN) &&
                (state != S_BRAKE_LINE) &&
                (state != S_BACKWARD) &&
                (state != S_ROTATE)) begin

                state <= S_BRAKE_LINE;
                timer <= '0;
                cmd   <= CMD_BRAKE;
                speed <= {PRECISION{1'b1}};

            end else begin
                case (state)

                    S_WAITBTN: begin
                        timer <= '0;
                        cmd   <= CMD_STOP;
                        speed <= '0;

                        if (button_start) begin
                            state <= S_IDLE;
                        end
                    end

                    S_IDLE: begin
                        timer <= '0;

                        if (nearest_center) begin
                            state <= S_FORWARD;
                            cmd   <= CMD_FORWARD;
                            speed <= center_attack_speed;
                        end else if (both_sides_without_center_equal) begin
                            state <= S_IDLE;
                            cmd   <= CMD_ROTATE;
                            speed <= SEARCH_SPEED;
                        end else if (nearest_right) begin
                            state <= S_TILTR;
                            cmd   <= CMD_TILTR;
                            speed <= TURN_SPEED;
                        end else if (nearest_left) begin
                            state <= S_TILTL;
                            cmd   <= CMD_TILTL;
                            speed <= TURN_SPEED;
                        end else begin
                            state <= S_IDLE;
                            cmd   <= CMD_ROTATE;
                            speed <= SEARCH_SPEED;
                        end
                    end

                    S_FORWARD: begin
                        timer <= '0;

                        if (nearest_center) begin
                            state <= S_FORWARD;
                            cmd   <= CMD_FORWARD;
                            speed <= center_attack_speed;
                        end else if (both_sides_without_center_equal) begin
                            state <= S_IDLE;
                            cmd   <= CMD_ROTATE;
                            speed <= SEARCH_SPEED;
                        end else if (nearest_right) begin
                            state <= S_TILTR;
                            cmd   <= CMD_TILTR;
                            speed <= TURN_SPEED;
                        end else if (nearest_left) begin
                            state <= S_TILTL;
                            cmd   <= CMD_TILTL;
                            speed <= TURN_SPEED;
                        end else begin
                            state <= S_IDLE;
                            cmd   <= CMD_ROTATE;
                            speed <= SEARCH_SPEED;
                        end
                    end
						  
						  /*
								Last-minute add-on: Small break state before the turn.
								Didn't go as expected, wheels hovered way too much. Too late to delete it before comp
						  */
                    S_BRAKE_LINE: begin
                        if (timer < BRAKE_LINE_TICKS_C) begin
                            timer <= timer + 1'b1;
                            cmd   <= CMD_BRAKE;
                            speed <= {PRECISION{1'b1}};
                        end else begin
                            state <= S_BACKWARD;
                            timer <= '0;
                            cmd   <= CMD_BACKWARD;
                            speed <= BACK_SPEED;
                        end
                    end

                    S_BACKWARD: begin
                        if (timer < BACKWARD_TICKS_C) begin
                            timer <= timer + 1'b1;
                            cmd   <= CMD_BACKWARD;
                            speed <= BACK_SPEED;
                        end else begin
                            state <= S_ROTATE;
                            timer <= '0;
                            cmd   <= CMD_ROTATE;
                            speed <= TURN_SPEED;
                        end
                    end

                    S_ROTATE: begin
                        if (timer < ROTATE_180_TICKS_C) begin
                            timer <= timer + 1'b1;
                            cmd   <= CMD_ROTATE;
                            speed <= TURN_SPEED;
                        end else begin
                            state <= S_IDLE;
                            timer <= '0;
                            cmd   <= CMD_ROTATE;
                            speed <= SEARCH_SPEED;
                        end
                    end

                    S_TILTR: begin
                        if (nearest_center) begin
                            state <= S_FORWARD;
                            timer <= '0;
                            cmd   <= CMD_FORWARD;
                            speed <= center_attack_speed;
                        end else if (both_sides_without_center_equal) begin
                            state <= S_IDLE;
                            timer <= '0;
                            cmd   <= CMD_ROTATE;
                            speed <= SEARCH_SPEED;
                        end else if (nearest_left) begin
                            state <= S_TILTL;
                            timer <= '0;
                            cmd   <= CMD_TILTL;
                            speed <= TURN_SPEED;
                        end else if (timer < TILT_45_TICKS_C) begin
                            timer <= timer + 1'b1;
                            cmd   <= CMD_TILTR;
                            speed <= TURN_SPEED;
                        end else begin
                            state <= S_IDLE;
                            timer <= '0;
                            cmd   <= CMD_ROTATE;
                            speed <= SEARCH_SPEED;
                        end
                    end

                    S_TILTL: begin
                        if (nearest_center) begin
                            state <= S_FORWARD;
                            timer <= '0;
                            cmd   <= CMD_FORWARD;
                            speed <= center_attack_speed;
                        end else if (both_sides_without_center_equal) begin
                            state <= S_IDLE;
                            timer <= '0;
                            cmd   <= CMD_ROTATE;
                            speed <= SEARCH_SPEED;
                        end else if (nearest_right) begin
                            state <= S_TILTR;
                            timer <= '0;
                            cmd   <= CMD_TILTR;
                            speed <= TURN_SPEED;
                        end else if (timer < TILT_45_TICKS_C) begin
                            timer <= timer + 1'b1;
                            cmd   <= CMD_TILTL;
                            speed <= TURN_SPEED;
                        end else begin
                            state <= S_IDLE;
                            timer <= '0;
                            cmd   <= CMD_ROTATE;
                            speed <= SEARCH_SPEED;
                        end
                    end

                    default: begin
                        state <= S_WAITBTN;
                        timer <= '0;
                        cmd   <= CMD_STOP;
                        speed <= '0;
                    end

                endcase
            end
        end
    end

endmodule

