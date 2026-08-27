module uart_fifo #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 16,
    parameter integer LEVEL_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
    input  wire                     clk_i,
    input  wire                     rst_n_i,
    input  wire                     clear_i,
    input  wire                     push_i,
    input  wire [WIDTH-1:0]         push_data_i,
    input  wire                     pop_i,
    output wire [WIDTH-1:0]         pop_data_o,
    output wire                     full_o,
    output wire                     empty_o,
    output reg  [LEVEL_WIDTH-1:0]   level_o,
    output reg                      overflow_o,
    output reg                      underflow_o
);

    localparam integer PTR_WIDTH = (DEPTH <= 2) ? 1 : $clog2(DEPTH);

    reg [WIDTH-1:0] memory [0:DEPTH-1];
    reg [PTR_WIDTH-1:0] write_ptr;
    reg [PTR_WIDTH-1:0] read_ptr;

    wire pop_accept  = pop_i && !empty_o;
    wire push_accept = push_i && (!full_o || pop_accept);

    assign pop_data_o = memory[read_ptr];
    assign empty_o = (level_o == 0);
    assign full_o  = (level_o == DEPTH);

    // Keep the storage write port synchronous and independent of reset so
    // synthesis tools can infer distributed RAM for deeper FIFO instances.
    always @(posedge clk_i) begin
        if (push_accept && !clear_i)
            memory[write_ptr] <= push_data_i;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_ptr   <= {PTR_WIDTH{1'b0}};
            read_ptr    <= {PTR_WIDTH{1'b0}};
            level_o     <= {LEVEL_WIDTH{1'b0}};
            overflow_o  <= 1'b0;
            underflow_o <= 1'b0;
        end else if (clear_i) begin
            write_ptr   <= {PTR_WIDTH{1'b0}};
            read_ptr    <= {PTR_WIDTH{1'b0}};
            level_o     <= {LEVEL_WIDTH{1'b0}};
            overflow_o  <= 1'b0;
            underflow_o <= 1'b0;
        end else begin
            overflow_o  <= push_i && full_o && !pop_accept;
            underflow_o <= pop_i && empty_o;

            if (push_accept) begin
                if (write_ptr == DEPTH - 1)
                    write_ptr <= {PTR_WIDTH{1'b0}};
                else
                    write_ptr <= write_ptr + 1'b1;
            end

            if (pop_accept) begin
                if (read_ptr == DEPTH - 1)
                    read_ptr <= {PTR_WIDTH{1'b0}};
                else
                    read_ptr <= read_ptr + 1'b1;
            end

            case ({push_accept, pop_accept})
                2'b10: level_o <= level_o + 1'b1;
                2'b01: level_o <= level_o - 1'b1;
                default: level_o <= level_o;
            endcase
        end
    end

endmodule
