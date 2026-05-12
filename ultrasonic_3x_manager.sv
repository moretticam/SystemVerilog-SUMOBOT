module ultrasonic_3x_manager #(
    parameter int F_CLK_HZ               = 50_000_000,
    parameter int STARTUP_DELAY_MS       = 100,
    parameter int DELAY_AFTER_MEASURE_MS = 60,
    parameter int SENSOR_TIMEOUT_MS      = 35,
    parameter int DETECT_DISTANCE_MM     = 500,
    parameter int MIN_VALID_DISTANCE_MM  = 20,
    parameter int TIMEOUT_DISTANCE_MM    = 4030
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,

    input  logic        echo_left,
    input  logic        echo_center,
    input  logic        echo_right,

    output logic        trig_left,
    output logic        trig_center,
    output logic        trig_right,

    output logic        detect_left,
    output logic        detect_center,
    output logic        detect_right,

    output logic [11:0] distance_left,
    output logic [11:0] distance_center,
    output logic [11:0] distance_right,

    output logic [1:0]  debug_sensor_active,
    output logic        debug_new_sample
);

    localparam int STARTUP_TICKS = (F_CLK_HZ / 1000) * STARTUP_DELAY_MS;
    localparam int DELAY_TICKS   = (F_CLK_HZ / 1000) * DELAY_AFTER_MEASURE_MS;

    localparam int STARTUP_W = (STARTUP_TICKS <= 1) ? 1 : $clog2(STARTUP_TICKS + 1);
    localparam int DELAY_W   = (DELAY_TICKS   <= 1) ? 1 : $clog2(DELAY_TICKS   + 1);

    typedef enum logic [2:0] {
        ST_STARTUP,
        ST_PULSE_LEFT,
        ST_WAIT_LEFT,
        ST_PULSE_CENTER,
        ST_WAIT_CENTER,
        ST_PULSE_RIGHT,
        ST_WAIT_RIGHT,
        ST_DELAY
    } state_t;

    typedef enum logic [1:0] {
        SENSOR_LEFT   = 2'd0,
        SENSOR_CENTER = 2'd1,
        SENSOR_RIGHT  = 2'd2
    } sensor_t;

    state_t  state;
    sensor_t next_sensor;

    logic [STARTUP_W-1:0] startup_cnt;
    logic [DELAY_W-1:0]   delay_cnt;

    logic read_left, read_center, read_right;
    logic new_left, new_center, new_right;

    logic [11:0] raw_distance_left;
    logic [11:0] raw_distance_center;
    logic [11:0] raw_distance_right;

    assign detect_left = enable &&
                         (distance_left >= MIN_VALID_DISTANCE_MM) &&
                         (distance_left <= DETECT_DISTANCE_MM) &&
                         (distance_left <  TIMEOUT_DISTANCE_MM);

    assign detect_center = enable &&
                           (distance_center >= MIN_VALID_DISTANCE_MM) &&
                           (distance_center <= DETECT_DISTANCE_MM) &&
                           (distance_center <  TIMEOUT_DISTANCE_MM);

    assign detect_right = enable &&
                          (distance_right >= MIN_VALID_DISTANCE_MM) &&
                          (distance_right <= DETECT_DISTANCE_MM) &&
                          (distance_right <  TIMEOUT_DISTANCE_MM);

    HC_SR04 #(.clk_freq(F_CLK_HZ), .TIMEOUT_MS(SENSOR_TIMEOUT_MS)) us_left_i (
        .rst_n(rst_n), .clk(clk), .read(read_left), .echo_in(echo_left),
        .trig(trig_left), .distance(raw_distance_left), .new_data(new_left)
    );

    HC_SR04 #(.clk_freq(F_CLK_HZ), .TIMEOUT_MS(SENSOR_TIMEOUT_MS)) us_center_i (
        .rst_n(rst_n), .clk(clk), .read(read_center), .echo_in(echo_center),
        .trig(trig_center), .distance(raw_distance_center), .new_data(new_center)
    );

    HC_SR04 #(.clk_freq(F_CLK_HZ), .TIMEOUT_MS(SENSOR_TIMEOUT_MS)) us_right_i (
        .rst_n(rst_n), .clk(clk), .read(read_right), .echo_in(echo_right),
        .trig(trig_right), .distance(raw_distance_right), .new_data(new_right)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= ST_STARTUP;
            next_sensor         <= SENSOR_LEFT;
            startup_cnt         <= '0;
            delay_cnt           <= '0;
            read_left           <= 1'b0;
            read_center         <= 1'b0;
            read_right          <= 1'b0;
            distance_left       <= 12'd4030;
            distance_center     <= 12'd4030;
            distance_right      <= 12'd4030;
            debug_sensor_active <= SENSOR_LEFT;
            debug_new_sample    <= 1'b0;
        end else begin
            read_left        <= 1'b0;
            read_center      <= 1'b0;
            read_right       <= 1'b0;
            debug_new_sample <= 1'b0;

            if (!enable) begin
                state       <= ST_STARTUP;
                startup_cnt <= '0;
                delay_cnt   <= '0;
            end else begin
                case (state)
                    ST_STARTUP: begin
                        debug_sensor_active <= SENSOR_LEFT;
                        if (startup_cnt >= STARTUP_TICKS - 1) begin
                            startup_cnt <= '0;
                            state       <= ST_PULSE_LEFT;
                        end else begin
                            startup_cnt <= startup_cnt + 1'b1;
                        end
                    end

                    ST_PULSE_LEFT: begin
                        read_left           <= 1'b1;
                        debug_sensor_active <= SENSOR_LEFT;
                        state               <= ST_WAIT_LEFT;
                    end

                    ST_WAIT_LEFT: begin
                        debug_sensor_active <= SENSOR_LEFT;
                        if (new_left) begin
                            distance_left    <= raw_distance_left;
                            debug_new_sample <= 1'b1;
                            next_sensor      <= SENSOR_CENTER;
                            delay_cnt        <= '0;
                            state            <= ST_DELAY;
                        end
                    end

                    ST_PULSE_CENTER: begin
                        read_center         <= 1'b1;
                        debug_sensor_active <= SENSOR_CENTER;
                        state               <= ST_WAIT_CENTER;
                    end

                    ST_WAIT_CENTER: begin
                        debug_sensor_active <= SENSOR_CENTER;
                        if (new_center) begin
                            distance_center  <= raw_distance_center;
                            debug_new_sample <= 1'b1;
                            next_sensor      <= SENSOR_RIGHT;
                            delay_cnt        <= '0;
                            state            <= ST_DELAY;
                        end
                    end

                    ST_PULSE_RIGHT: begin
                        read_right          <= 1'b1;
                        debug_sensor_active <= SENSOR_RIGHT;
                        state               <= ST_WAIT_RIGHT;
                    end

                    ST_WAIT_RIGHT: begin
                        debug_sensor_active <= SENSOR_RIGHT;
                        if (new_right) begin
                            distance_right   <= raw_distance_right;
                            debug_new_sample <= 1'b1;
                            next_sensor      <= SENSOR_LEFT;
                            delay_cnt        <= '0;
                            state            <= ST_DELAY;
                        end
                    end

                    ST_DELAY: begin
                        if (delay_cnt >= DELAY_TICKS - 1) begin
                            delay_cnt <= '0;
                            case (next_sensor)
                                SENSOR_LEFT:   state <= ST_PULSE_LEFT;
                                SENSOR_CENTER: state <= ST_PULSE_CENTER;
                                SENSOR_RIGHT:  state <= ST_PULSE_RIGHT;
                                default:       state <= ST_PULSE_LEFT;
                            endcase
                        end else begin
                            delay_cnt <= delay_cnt + 1'b1;
                        end
                    end

                    default: begin
                        state <= ST_STARTUP;
                    end
                endcase
            end
        end
    end

endmodule