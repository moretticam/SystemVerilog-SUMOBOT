
module HC_SR04 #(
    parameter int clk_freq   = 50_000_000,
    parameter int TIMEOUT_MS = 35
)(
    input  logic            rst_n,
    input  logic            clk,
    input  logic            read,
    input  logic            echo_in,

    output logic            trig,
    output logic [11:0]     distance,
    output logic            new_data
);

    localparam int clk_cycles_1us     = clk_freq / 1_000_000;
    localparam int width_1us_counter  = (clk_cycles_1us <= 1) ? 1 : $clog2(clk_cycles_1us);
    localparam int clk_cycles_1mm     = (clk_cycles_1us * 583) / 100;
    localparam int width_1mm_counter  = (clk_cycles_1mm <= 1) ? 1 : $clog2(clk_cycles_1mm);
    localparam int clk_cycles_10us    = 10 * clk_cycles_1us;
    localparam int width_10us_counter = (clk_cycles_10us <= 1) ? 1 : $clog2(clk_cycles_10us);

    localparam logic [11:0] timeout_limit = 12'd4030;

    localparam int TIMEOUT_TICKS = (clk_freq / 1000) * TIMEOUT_MS;
    localparam int TIMEOUT_W     = (TIMEOUT_TICKS <= 1) ? 1 : $clog2(TIMEOUT_TICKS + 1);

    logic echo_sync, echo;

    always_ff @(posedge clk) begin
        echo_sync <= echo_in;
        echo      <= echo_sync;
    end

    logic [(width_1mm_counter  - 1):0] counter_1mm;
    logic [(width_1us_counter  - 1):0] counter_1us;
    logic [(width_10us_counter - 1):0] counter_10us;
    logic [(TIMEOUT_W          - 1):0] timeout_counter;

    typedef enum logic [1:0] {
        WAIT,
        MEASURE_INIT,
        MEASURE
    } state_t;

    state_t state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            new_data        <= 1'b0;
            trig            <= 1'b0;
            distance        <= '0;
            counter_1mm     <= '0;
            counter_1us     <= '0;
            counter_10us    <= '0;
            timeout_counter <= '0;
            state           <= WAIT;
        end else begin
            case (state)
                WAIT: begin
                    new_data        <= 1'b0;
                    trig            <= 1'b0;
                    counter_1mm     <= '0;
                    counter_1us     <= '0;
                    counter_10us    <= '0;
                    timeout_counter <= '0;

                    if (read) begin
                        state    <= MEASURE_INIT;
                        distance <= '0;
                        trig     <= 1'b1;
                    end
                end

                MEASURE_INIT: begin
                    new_data <= 1'b0;

                    // 10us TRIG pulse
                    if (trig) begin
                        if (counter_10us >= clk_cycles_10us - 1) begin
                            trig         <= 1'b0;
                            counter_10us <= '0;
                        end else begin
                            counter_10us <= counter_10us + 1'b1;
                        end
                    end

                    // Timeout before ECHO beginning.
                    if (timeout_counter >= TIMEOUT_TICKS - 1) begin
                        state           <= WAIT;
                        new_data        <= 1'b1;
                        distance        <= timeout_limit;
                        timeout_counter <= '0;
                        counter_1us     <= '0;
                    end else begin
                        timeout_counter <= timeout_counter + 1'b1;

                        if (echo) begin
                            if (counter_1us >= clk_cycles_1us - 1) begin
                                state           <= MEASURE;
                                counter_1us     <= '0;
                                timeout_counter <= '0;
                            end else begin
                                counter_1us <= counter_1us + 1'b1;
                            end
                        end else begin
                            counter_1us <= '0;
                        end
                    end
                end

                MEASURE: begin
                    new_data <= 1'b0;

                    if (!echo) begin
                        if (counter_1us >= clk_cycles_1us - 1) begin
                            state       <= WAIT;
                            new_data    <= 1'b1;
                            counter_1us <= '0;
                        end else begin
                            counter_1us <= counter_1us + 1'b1;
                        end
                    end else begin
                        counter_1us <= '0;
                    end

                    if (counter_1mm >= clk_cycles_1mm - 1) begin
                        if (distance < timeout_limit) begin
                            distance <= distance + 1'b1;
                        end
                        counter_1mm <= '0;
                    end else begin
                        counter_1mm <= counter_1mm + 1'b1;
                    end

                    if (distance >= timeout_limit) begin
                        state    <= WAIT;
                        new_data <= 1'b1;
                    end
                end

                default: begin
                    state <= WAIT;
                end
            endcase
        end
    end

endmodule
