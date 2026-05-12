module pwm #(
    parameter int PRECISION = 10,
    parameter int F_CLK_HZ  = 50_000_000
)   (
    input  logic                     rst_n,
    input  logic                     clk,
    input  logic [(PRECISION-1):0]   power_value, // 0 to 1023 with 10 bit precision
    output logic                     pwm_out
);

    logic [(PRECISION-1):0] counter;
    logic [(PRECISION-1):0] counter_max = '1;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            counter <= 'd1;
        end

        else if(counter <= counter_max - 1'b1) begin
            counter <= counter + 1'b1;
        end

        else begin 
            counter <= 'd1;
        end 
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pwm_out <= '0;
        end

        else if (counter > power_value) begin
            pwm_out <= '0;
        end

        else begin
            pwm_out <= '1;
        end 
    end

endmodule