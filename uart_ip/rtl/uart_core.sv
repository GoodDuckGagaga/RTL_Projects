module uart_core #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer DEFAULT_BAUD = 115_200,
    parameter integer OVERSAMPLE = 16,
    parameter integer DIV_WIDTH = 24,
    parameter integer TX_FIFO_DEPTH = 16,
    parameter integer RX_FIFO_DEPTH = 16,
    parameter integer RTS_MARGIN = 2,
    parameter [3:0] DEFAULT_DATA_BITS = 4'd8,
    parameter [2:0] DEFAULT_PARITY = 3'd0,
    parameter [1:0] DEFAULT_STOP_BITS = 2'd1
) (
    input  wire                              clk_i,
    input  wire                              rst_n_i,

    input  wire                              cfg_valid_i,
    output wire                              cfg_ready_o,
    input  wire [DIV_WIDTH-1:0]              cfg_baud_divisor_i,
    input  wire [3:0]                        cfg_data_bits_i,
    input  wire [2:0]                        cfg_parity_i,
    input  wire [1:0]                        cfg_stop_bits_i,
    input  wire                              cfg_flow_control_i,
    input  wire                              cfg_loopback_i,
    output reg                               cfg_applied_o,

    input  wire                              tx_valid_i,
    output wire                              tx_ready_o,
    input  wire [8:0]                        tx_data_i,
    input  wire                              tx_break_i,
    input  wire                              tx_flush_i,
    output wire                              tx_o,
    output wire                              tx_de_o,
    output wire                              tx_busy_o,
    output wire                              tx_done_o,
    output wire [$clog2(TX_FIFO_DEPTH+1)-1:0] tx_level_o,

    input  wire                              rx_i,
    input  wire                              rx_ready_i,
    output wire                              rx_valid_o,
    output wire [8:0]                        rx_data_o,
    output wire                              rx_parity_error_o,
    output wire                              rx_framing_error_o,
    output wire                              rx_break_o,
    input  wire                              rx_flush_i,
    input  wire                              clear_errors_i,
    output reg                               rx_overrun_o,
    output wire                              rx_busy_o,
    output wire [$clog2(RX_FIFO_DEPTH+1)-1:0] rx_level_o,

    input  wire                              cts_n_i,
    output wire                              rts_n_o
);

    localparam integer DEFAULT_DIVISOR_CALC =
        (CLK_HZ + ((DEFAULT_BAUD * OVERSAMPLE) / 2)) /
        (DEFAULT_BAUD * OVERSAMPLE);
    localparam integer RTS_BLOCK_LEVEL =
        (RX_FIFO_DEPTH > RTS_MARGIN) ? (RX_FIFO_DEPTH - RTS_MARGIN) : 1;
    localparam integer RX_ENTRY_WIDTH = 12;

    reg [DIV_WIDTH-1:0] baud_divisor_cfg;
    reg [3:0] data_bits_cfg;
    reg [2:0] parity_cfg;
    reg [1:0] stop_bits_cfg;
    reg       flow_control_cfg;
    reg       loopback_cfg;

    reg rx_meta;
    reg rx_sync;
    reg cts_meta;
    reg cts_sync;

    wire os_tick;
    wire cfg_apply = cfg_valid_i && cfg_ready_o;

    wire tx_fifo_full;
    wire tx_fifo_empty;
    wire [8:0] tx_fifo_data;
    wire tx_fifo_pop;
    wire tx_fifo_overflow_unused;
    wire tx_fifo_underflow_unused;

    wire tx_engine_line;
    wire tx_engine_busy;
    wire tx_engine_done;
    wire tx_engine_start;

    wire rx_selected = loopback_cfg ? tx_o : rx_i;
    wire rx_frame_valid;
    wire [8:0] rx_frame_data;
    wire rx_frame_parity_error;
    wire rx_frame_framing_error;
    wire rx_frame_break;

    wire rx_fifo_full;
    wire rx_fifo_empty;
    wire [RX_ENTRY_WIDTH-1:0] rx_fifo_data;
    wire rx_fifo_pop;
    wire rx_fifo_overflow;
    wire rx_fifo_underflow_unused;

    function automatic [DIV_WIDTH-1:0] clamp_divisor;
        input [DIV_WIDTH-1:0] value;
        begin
            clamp_divisor = (value < 2) ? 2 : value;
        end
    endfunction

    function automatic [3:0] clamp_data_bits;
        input [3:0] value;
        begin
            if (value < 5)
                clamp_data_bits = 4'd5;
            else if (value > 9)
                clamp_data_bits = 4'd9;
            else
                clamp_data_bits = value;
        end
    endfunction

    function automatic [2:0] clamp_parity;
        input [2:0] value;
        begin
            clamp_parity = (value > 4) ? 3'd0 : value;
        end
    endfunction

    function automatic [1:0] clamp_stop_bits;
        input [1:0] value;
        begin
            clamp_stop_bits = (value == 2) ? 2'd2 : 2'd1;
        end
    endfunction

    assign cfg_ready_o = !tx_engine_busy && tx_fifo_empty &&
                         !rx_busy_o && rx_sync && !tx_break_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            baud_divisor_cfg <= (DEFAULT_DIVISOR_CALC < 2) ? 2 : DEFAULT_DIVISOR_CALC;
            data_bits_cfg    <= clamp_data_bits(DEFAULT_DATA_BITS);
            parity_cfg       <= clamp_parity(DEFAULT_PARITY);
            stop_bits_cfg    <= clamp_stop_bits(DEFAULT_STOP_BITS);
            flow_control_cfg <= 1'b0;
            loopback_cfg     <= 1'b0;
            cfg_applied_o    <= 1'b0;
        end else begin
            cfg_applied_o <= 1'b0;
            if (cfg_apply) begin
                baud_divisor_cfg <= clamp_divisor(cfg_baud_divisor_i);
                data_bits_cfg    <= clamp_data_bits(cfg_data_bits_i);
                parity_cfg       <= clamp_parity(cfg_parity_i);
                stop_bits_cfg    <= clamp_stop_bits(cfg_stop_bits_i);
                flow_control_cfg <= cfg_flow_control_i;
                loopback_cfg     <= cfg_loopback_i;
                cfg_applied_o    <= 1'b1;
            end
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rx_meta  <= 1'b1;
            rx_sync  <= 1'b1;
            cts_meta <= 1'b1;
            cts_sync <= 1'b1;
        end else begin
            rx_meta  <= rx_selected;
            rx_sync  <= rx_meta;
            cts_meta <= cts_n_i;
            cts_sync <= cts_meta;
        end
    end

    uart_tick_gen #(
        .DIV_WIDTH(DIV_WIDTH)
    ) u_tick_gen (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(1'b1),
        .restart_i(cfg_apply),
        .divisor_i(baud_divisor_cfg),
        .tick_o(os_tick)
    );

    assign tx_ready_o = !tx_fifo_full;
    assign tx_engine_start = !tx_engine_busy && !tx_fifo_empty &&
                             !tx_break_i &&
                             (!flow_control_cfg || !cts_sync);
    assign tx_fifo_pop = tx_engine_start;

    uart_fifo #(
        .WIDTH(9),
        .DEPTH(TX_FIFO_DEPTH)
    ) u_tx_fifo (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_i(tx_flush_i),
        .push_i(tx_valid_i && tx_ready_o),
        .push_data_i(tx_data_i),
        .pop_i(tx_fifo_pop),
        .pop_data_o(tx_fifo_data),
        .full_o(tx_fifo_full),
        .empty_o(tx_fifo_empty),
        .level_o(tx_level_o),
        .overflow_o(tx_fifo_overflow_unused),
        .underflow_o(tx_fifo_underflow_unused)
    );

    uart_tx_engine #(
        .OVERSAMPLE(OVERSAMPLE)
    ) u_tx_engine (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .os_tick_i(os_tick),
        .start_i(tx_engine_start),
        .data_i(tx_fifo_data),
        .data_bits_i(data_bits_cfg),
        .parity_mode_i(parity_cfg),
        .stop_bits_i(stop_bits_cfg),
        .tx_o(tx_engine_line),
        .busy_o(tx_engine_busy),
        .done_o(tx_engine_done)
    );

    assign tx_o      = tx_engine_busy ? tx_engine_line : (tx_break_i ? 1'b0 : 1'b1);
    assign tx_de_o   = tx_engine_busy || tx_break_i;
    assign tx_busy_o = tx_engine_busy || !tx_fifo_empty || tx_break_i;
    assign tx_done_o = tx_engine_done;

    uart_rx_engine #(
        .OVERSAMPLE(OVERSAMPLE)
    ) u_rx_engine (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .os_tick_i(os_tick),
        .rx_i(rx_sync),
        .data_bits_i(data_bits_cfg),
        .parity_mode_i(parity_cfg),
        .stop_bits_i(stop_bits_cfg),
        .frame_valid_o(rx_frame_valid),
        .data_o(rx_frame_data),
        .parity_error_o(rx_frame_parity_error),
        .framing_error_o(rx_frame_framing_error),
        .break_o(rx_frame_break),
        .busy_o(rx_busy_o)
    );

    assign rx_fifo_pop = rx_valid_o && rx_ready_i;
    assign rx_valid_o = !rx_fifo_empty;
    assign rx_data_o = rx_fifo_data[8:0];
    assign rx_parity_error_o = rx_fifo_data[9];
    assign rx_framing_error_o = rx_fifo_data[10];
    assign rx_break_o = rx_fifo_data[11];

    uart_fifo #(
        .WIDTH(RX_ENTRY_WIDTH),
        .DEPTH(RX_FIFO_DEPTH)
    ) u_rx_fifo (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_i(rx_flush_i),
        .push_i(rx_frame_valid),
        .push_data_i({rx_frame_break, rx_frame_framing_error,
                      rx_frame_parity_error, rx_frame_data}),
        .pop_i(rx_fifo_pop),
        .pop_data_o(rx_fifo_data),
        .full_o(rx_fifo_full),
        .empty_o(rx_fifo_empty),
        .level_o(rx_level_o),
        .overflow_o(rx_fifo_overflow),
        .underflow_o(rx_fifo_underflow_unused)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            rx_overrun_o <= 1'b0;
        else if (clear_errors_i || rx_flush_i)
            rx_overrun_o <= 1'b0;
        else if (rx_fifo_overflow)
            rx_overrun_o <= 1'b1;
    end

    assign rts_n_o = !flow_control_cfg ? 1'b0 :
                     ((rx_level_o >= RTS_BLOCK_LEVEL) ? 1'b1 : 1'b0);

endmodule
