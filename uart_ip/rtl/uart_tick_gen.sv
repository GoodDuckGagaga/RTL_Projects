module uart_tick_gen #(
    parameter integer DIV_WIDTH = 24
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,
    input  wire                 enable_i,
    input  wire                 restart_i,
    input  wire [DIV_WIDTH-1:0] divisor_i,
    output reg                  tick_o
);

    reg [DIV_WIDTH-1:0] counter;
    wire [DIV_WIDTH-1:0] divisor_safe = (divisor_i < 2) ? 2 : divisor_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            counter <= {DIV_WIDTH{1'b0}};
            tick_o  <= 1'b0;
        end else if (!enable_i || restart_i) begin
            counter <= {DIV_WIDTH{1'b0}};
            tick_o  <= 1'b0;
        end else if (counter >= divisor_safe - 1'b1) begin
            counter <= {DIV_WIDTH{1'b0}};
            tick_o  <= 1'b1;
        end else begin
            counter <= counter + 1'b1;
            tick_o  <= 1'b0;
        end
    end

endmodule
