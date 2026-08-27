module uart_tx_engine #(
    parameter integer OVERSAMPLE = 16
) (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        os_tick_i,
    input  wire        start_i,
    input  wire [8:0]  data_i,
    input  wire [3:0]  data_bits_i,
    input  wire [2:0]  parity_mode_i,
    input  wire [1:0]  stop_bits_i,
    output reg         tx_o,
    output reg         busy_o,
    output reg         done_o
);

    localparam [2:0] STATE_IDLE   = 3'd0;
    localparam [2:0] STATE_START  = 3'd1;
    localparam [2:0] STATE_DATA   = 3'd2;
    localparam [2:0] STATE_PARITY = 3'd3;
    localparam [2:0] STATE_STOP   = 3'd4;

    localparam [2:0] PARITY_NONE  = 3'd0;
    localparam [2:0] PARITY_EVEN  = 3'd1;
    localparam [2:0] PARITY_ODD   = 3'd2;
    localparam [2:0] PARITY_MARK  = 3'd3;
    localparam [2:0] PARITY_SPACE = 3'd4;

    localparam integer OS_COUNT_WIDTH = (OVERSAMPLE <= 2) ? 1 : $clog2(OVERSAMPLE);

    reg [2:0] state;
    reg [OS_COUNT_WIDTH-1:0] os_count;
    reg [3:0] bit_index;
    reg [1:0] stop_index;
    reg [8:0] data_reg;
    reg [3:0] data_bits_reg;
    reg [2:0] parity_mode_reg;
    reg [1:0] stop_bits_reg;
    reg       parity_reg;

    function automatic parity_value;
        input [8:0] data_value;
        input [3:0] data_bits_value;
        input [2:0] parity_mode_value;
        integer index;
        reg xor_value;
        begin
            xor_value = 1'b0;
            for (index = 0; index < 9; index = index + 1) begin
                if (index < data_bits_value)
                    xor_value = xor_value ^ data_value[index];
            end

            case (parity_mode_value)
                PARITY_EVEN:  parity_value = xor_value;
                PARITY_ODD:   parity_value = ~xor_value;
                PARITY_MARK:  parity_value = 1'b1;
                PARITY_SPACE: parity_value = 1'b0;
                default:      parity_value = 1'b0;
            endcase
        end
    endfunction

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state           <= STATE_IDLE;
            os_count        <= {OS_COUNT_WIDTH{1'b0}};
            bit_index       <= 4'd0;
            stop_index      <= 2'd0;
            data_reg        <= 9'd0;
            data_bits_reg   <= 4'd8;
            parity_mode_reg <= PARITY_NONE;
            stop_bits_reg   <= 2'd1;
            parity_reg      <= 1'b0;
            tx_o            <= 1'b1;
            busy_o          <= 1'b0;
            done_o          <= 1'b0;
        end else begin
            done_o <= 1'b0;

            if (!busy_o) begin
                tx_o <= 1'b1;
                if (start_i) begin
                    state           <= STATE_START;
                    os_count        <= {OS_COUNT_WIDTH{1'b0}};
                    bit_index       <= 4'd0;
                    stop_index      <= 2'd0;
                    data_reg        <= data_i;
                    data_bits_reg   <= data_bits_i;
                    parity_mode_reg <= parity_mode_i;
                    stop_bits_reg   <= stop_bits_i;
                    parity_reg      <= parity_value(data_i, data_bits_i, parity_mode_i);
                    tx_o            <= 1'b0;
                    busy_o          <= 1'b1;
                end
            end else if (os_tick_i) begin
                if (os_count == OVERSAMPLE - 1) begin
                    os_count <= {OS_COUNT_WIDTH{1'b0}};

                    case (state)
                        STATE_START: begin
                            state     <= STATE_DATA;
                            bit_index <= 4'd0;
                            tx_o      <= data_reg[0];
                        end

                        STATE_DATA: begin
                            if (bit_index + 1 >= data_bits_reg) begin
                                if (parity_mode_reg == PARITY_NONE) begin
                                    state      <= STATE_STOP;
                                    stop_index <= 2'd0;
                                    tx_o       <= 1'b1;
                                end else begin
                                    state <= STATE_PARITY;
                                    tx_o  <= parity_reg;
                                end
                            end else begin
                                bit_index <= bit_index + 1'b1;
                                tx_o      <= data_reg[bit_index + 1'b1];
                            end
                        end

                        STATE_PARITY: begin
                            state      <= STATE_STOP;
                            stop_index <= 2'd0;
                            tx_o       <= 1'b1;
                        end

                        STATE_STOP: begin
                            tx_o <= 1'b1;
                            if (stop_index + 1 >= stop_bits_reg) begin
                                state  <= STATE_IDLE;
                                busy_o <= 1'b0;
                                done_o <= 1'b1;
                            end else begin
                                stop_index <= stop_index + 1'b1;
                            end
                        end

                        default: begin
                            state  <= STATE_IDLE;
                            tx_o   <= 1'b1;
                            busy_o <= 1'b0;
                        end
                    endcase
                end else begin
                    os_count <= os_count + 1'b1;
                end
            end
        end
    end

endmodule
