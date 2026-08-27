module uart_rx_engine #(
    parameter integer OVERSAMPLE = 16
) (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        os_tick_i,
    input  wire        rx_i,
    input  wire [3:0]  data_bits_i,
    input  wire [2:0]  parity_mode_i,
    input  wire [1:0]  stop_bits_i,
    output reg         frame_valid_o,
    output reg  [8:0]  data_o,
    output reg         parity_error_o,
    output reg         framing_error_o,
    output reg         break_o,
    output wire        busy_o
);

    localparam [2:0] STATE_IDLE       = 3'd0;
    localparam [2:0] STATE_START      = 3'd1;
    localparam [2:0] STATE_DATA       = 3'd2;
    localparam [2:0] STATE_PARITY     = 3'd3;
    localparam [2:0] STATE_STOP       = 3'd4;
    localparam [2:0] STATE_BREAK_WAIT = 3'd5;

    localparam [2:0] PARITY_NONE  = 3'd0;
    localparam [2:0] PARITY_EVEN  = 3'd1;
    localparam [2:0] PARITY_ODD   = 3'd2;
    localparam [2:0] PARITY_MARK  = 3'd3;
    localparam [2:0] PARITY_SPACE = 3'd4;

    localparam integer OS_COUNT_WIDTH = (OVERSAMPLE <= 2) ? 1 : $clog2(OVERSAMPLE);
    localparam integer SAMPLE_A = (OVERSAMPLE / 2) - 1;
    localparam integer SAMPLE_B = (OVERSAMPLE / 2);
    localparam integer SAMPLE_C = (OVERSAMPLE / 2) + 1;

    reg [2:0] state;
    reg [OS_COUNT_WIDTH-1:0] os_count;
    reg [1:0] vote_count;
    reg [3:0] bit_index;
    reg [1:0] stop_index;
    reg [8:0] data_reg;
    reg       parity_xor_reg;
    reg       parity_error_reg;
    reg       framing_error_reg;
    reg [3:0] data_bits_reg;
    reg [2:0] parity_mode_reg;
    reg [1:0] stop_bits_reg;

    wire at_sample_point = (os_count == SAMPLE_A) ||
                           (os_count == SAMPLE_B) ||
                           (os_count == SAMPLE_C);
    wire voted_bit = (vote_count >= 2);

    assign busy_o = (state != STATE_IDLE);

    function automatic expected_parity;
        input parity_xor_value;
        input [2:0] parity_mode_value;
        begin
            case (parity_mode_value)
                PARITY_EVEN:  expected_parity = parity_xor_value;
                PARITY_ODD:   expected_parity = ~parity_xor_value;
                PARITY_MARK:  expected_parity = 1'b1;
                PARITY_SPACE: expected_parity = 1'b0;
                default:      expected_parity = 1'b0;
            endcase
        end
    endfunction

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state               <= STATE_IDLE;
            os_count            <= {OS_COUNT_WIDTH{1'b0}};
            vote_count          <= 2'd0;
            bit_index           <= 4'd0;
            stop_index          <= 2'd0;
            data_reg            <= 9'd0;
            parity_xor_reg      <= 1'b0;
            parity_error_reg    <= 1'b0;
            framing_error_reg   <= 1'b0;
            data_bits_reg       <= 4'd8;
            parity_mode_reg     <= PARITY_NONE;
            stop_bits_reg       <= 2'd1;
            frame_valid_o       <= 1'b0;
            data_o              <= 9'd0;
            parity_error_o      <= 1'b0;
            framing_error_o     <= 1'b0;
            break_o             <= 1'b0;
        end else begin
            frame_valid_o <= 1'b0;

            if (state == STATE_IDLE) begin
                os_count   <= {OS_COUNT_WIDTH{1'b0}};
                vote_count <= 2'd0;

                if (!rx_i) begin
                    state               <= STATE_START;
                    bit_index           <= 4'd0;
                    stop_index          <= 2'd0;
                    data_reg            <= 9'd0;
                    parity_xor_reg      <= 1'b0;
                    parity_error_reg    <= 1'b0;
                    framing_error_reg   <= 1'b0;
                    data_bits_reg       <= data_bits_i;
                    parity_mode_reg     <= parity_mode_i;
                    stop_bits_reg       <= stop_bits_i;
                end
            end else if (state == STATE_BREAK_WAIT) begin
                if (rx_i)
                    state <= STATE_IDLE;
            end else if (os_tick_i) begin
                if (at_sample_point && rx_i)
                    vote_count <= vote_count + 1'b1;

                if (os_count == OVERSAMPLE - 1) begin
                    os_count   <= {OS_COUNT_WIDTH{1'b0}};
                    vote_count <= 2'd0;

                    case (state)
                        STATE_START: begin
                            if (!voted_bit) begin
                                state     <= STATE_DATA;
                                bit_index <= 4'd0;
                            end else begin
                                state <= STATE_IDLE;
                            end
                        end

                        STATE_DATA: begin
                            data_reg[bit_index] <= voted_bit;
                            parity_xor_reg <= parity_xor_reg ^ voted_bit;

                            if (bit_index + 1 >= data_bits_reg) begin
                                if (parity_mode_reg == PARITY_NONE) begin
                                    state      <= STATE_STOP;
                                    stop_index <= 2'd0;
                                end else begin
                                    state <= STATE_PARITY;
                                end
                            end else begin
                                bit_index <= bit_index + 1'b1;
                            end
                        end

                        STATE_PARITY: begin
                            if (voted_bit != expected_parity(parity_xor_reg, parity_mode_reg))
                                parity_error_reg <= 1'b1;
                            state      <= STATE_STOP;
                            stop_index <= 2'd0;
                        end

                        STATE_STOP: begin
                            if (!voted_bit)
                                framing_error_reg <= 1'b1;

                            if (stop_index + 1 >= stop_bits_reg) begin
                                data_o          <= data_reg;
                                parity_error_o  <= parity_error_reg;
                                framing_error_o <= framing_error_reg || !voted_bit;
                                break_o         <= (framing_error_reg || !voted_bit) && (data_reg == 0);
                                frame_valid_o   <= 1'b1;

                                if ((framing_error_reg || !voted_bit) && (data_reg == 0) && !rx_i)
                                    state <= STATE_BREAK_WAIT;
                                else
                                    state <= STATE_IDLE;
                            end else begin
                                stop_index <= stop_index + 1'b1;
                            end
                        end

                        default: state <= STATE_IDLE;
                    endcase
                end else begin
                    os_count <= os_count + 1'b1;
                end
            end
        end
    end

endmodule
