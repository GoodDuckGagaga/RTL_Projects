module tb_uart_core;
    timeunit 1ns;
    timeprecision 1ps;

    localparam integer OVERSAMPLE = 8;
    localparam integer DIV_WIDTH = 16;
    localparam integer DIVISOR = 4;

    localparam [2:0] PARITY_NONE = 3'd0;
    localparam [2:0] PARITY_EVEN = 3'd1;
    localparam [2:0] PARITY_ODD  = 3'd2;
    localparam [2:0] PARITY_MARK = 3'd3;

    reg clk;
    reg rst_n;

    reg cfg_valid;
    wire cfg_ready;
    reg [DIV_WIDTH-1:0] cfg_divisor;
    reg [3:0] cfg_data_bits;
    reg [2:0] cfg_parity;
    reg [1:0] cfg_stop_bits;
    reg cfg_flow_control;
    reg cfg_loopback;
    wire cfg_applied;

    reg tx_valid;
    wire tx_ready;
    reg [8:0] tx_data;
    reg tx_break;
    reg tx_flush;
    wire tx_o;
    wire tx_de;
    wire tx_busy;
    wire tx_done;
    wire [2:0] tx_level;

    reg external_loopback;
    wire rx_pin = external_loopback ? tx_o : 1'b1;
    reg rx_ready;
    wire rx_valid;
    wire [8:0] rx_data;
    wire rx_parity_error;
    wire rx_framing_error;
    wire rx_break;
    reg rx_flush;
    reg clear_errors;
    wire rx_overrun;
    wire rx_busy;
    wire [2:0] rx_level;

    reg cts_n;
    wire rts_n;

    integer error_count;
    integer wait_count;

    uart_core #(
        .CLK_HZ(100_000_000),
        .DEFAULT_BAUD(3_125_000),
        .OVERSAMPLE(OVERSAMPLE),
        .DIV_WIDTH(DIV_WIDTH),
        .TX_FIFO_DEPTH(4),
        .RX_FIFO_DEPTH(4),
        .RTS_MARGIN(1)
    ) dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cfg_valid_i(cfg_valid),
        .cfg_ready_o(cfg_ready),
        .cfg_baud_divisor_i(cfg_divisor),
        .cfg_data_bits_i(cfg_data_bits),
        .cfg_parity_i(cfg_parity),
        .cfg_stop_bits_i(cfg_stop_bits),
        .cfg_flow_control_i(cfg_flow_control),
        .cfg_loopback_i(cfg_loopback),
        .cfg_applied_o(cfg_applied),
        .tx_valid_i(tx_valid),
        .tx_ready_o(tx_ready),
        .tx_data_i(tx_data),
        .tx_break_i(tx_break),
        .tx_flush_i(tx_flush),
        .tx_o(tx_o),
        .tx_de_o(tx_de),
        .tx_busy_o(tx_busy),
        .tx_done_o(tx_done),
        .tx_level_o(tx_level),
        .rx_i(rx_pin),
        .rx_ready_i(rx_ready),
        .rx_valid_o(rx_valid),
        .rx_data_o(rx_data),
        .rx_parity_error_o(rx_parity_error),
        .rx_framing_error_o(rx_framing_error),
        .rx_break_o(rx_break),
        .rx_flush_i(rx_flush),
        .clear_errors_i(clear_errors),
        .rx_overrun_o(rx_overrun),
        .rx_busy_o(rx_busy),
        .rx_level_o(rx_level),
        .cts_n_i(cts_n),
        .rts_n_o(rts_n)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic apply_config;
        input [3:0] data_bits_value;
        input [2:0] parity_value;
        input [1:0] stop_bits_value;
        input       flow_control_value;
        input       loopback_value;
        begin
            @(negedge clk);
            while (!cfg_ready)
                @(negedge clk);

            cfg_divisor      = DIVISOR;
            cfg_data_bits    = data_bits_value;
            cfg_parity       = parity_value;
            cfg_stop_bits    = stop_bits_value;
            cfg_flow_control = flow_control_value;
            cfg_loopback     = loopback_value;
            cfg_valid        = 1'b1;
            @(negedge clk);
            cfg_valid        = 1'b0;
        end
    endtask

    task automatic send_byte;
        input [8:0] value;
        begin
            @(negedge clk);
            while (!tx_ready)
                @(negedge clk);
            tx_data  = value;
            tx_valid = 1'b1;
            @(negedge clk);
            tx_valid = 1'b0;
        end
    endtask

    task automatic expect_byte;
        input [8:0] expected_data;
        input       expected_parity_error;
        input       expected_framing_error;
        input       expected_break;
        begin
            wait_count = 0;
            @(negedge clk);
            while (!rx_valid && wait_count < 5000) begin
                wait_count = wait_count + 1;
                @(negedge clk);
            end

            if (!rx_valid) begin
                $display("FAIL: receive timeout");
                error_count = error_count + 1;
            end else begin
                if (rx_data !== expected_data ||
                    rx_parity_error !== expected_parity_error ||
                    rx_framing_error !== expected_framing_error ||
                    rx_break !== expected_break) begin
                    $display("FAIL: RX data=%03h p=%b f=%b b=%b, expected=%03h/%b/%b/%b",
                             rx_data, rx_parity_error, rx_framing_error, rx_break,
                             expected_data, expected_parity_error,
                             expected_framing_error, expected_break);
                    error_count = error_count + 1;
                end

                rx_ready = 1'b1;
                @(negedge clk);
                rx_ready = 1'b0;
            end
        end
    endtask

    initial begin
        rst_n            = 1'b0;
        cfg_valid        = 1'b0;
        cfg_divisor      = DIVISOR;
        cfg_data_bits    = 4'd8;
        cfg_parity       = PARITY_NONE;
        cfg_stop_bits    = 2'd1;
        cfg_flow_control = 1'b0;
        cfg_loopback     = 1'b0;
        tx_valid         = 1'b0;
        tx_data          = 9'd0;
        tx_break         = 1'b0;
        tx_flush         = 1'b0;
        external_loopback = 1'b0;
        rx_ready         = 1'b0;
        rx_flush         = 1'b0;
        clear_errors     = 1'b0;
        cts_n            = 1'b0;
        error_count      = 0;

        repeat (10) @(negedge clk);
        rst_n = 1'b1;

        // Internal loopback: 8 data bits, even parity, one stop bit.
        apply_config(4'd8, PARITY_EVEN, 2'd1, 1'b0, 1'b1);
        send_byte(9'h055);
        expect_byte(9'h055, 1'b0, 1'b0, 1'b0);
        send_byte(9'h1a3);
        expect_byte(9'h0a3, 1'b0, 1'b0, 1'b0);

        // Pin-level loopback: 7 data bits, odd parity, two stop bits.
        external_loopback = 1'b1;
        apply_config(4'd7, PARITY_ODD, 2'd2, 1'b0, 1'b0);
        send_byte(9'h053);
        expect_byte(9'h053, 1'b0, 1'b0, 1'b0);

        // Nine-bit mode with mark parity.
        external_loopback = 1'b0;
        apply_config(4'd9, PARITY_MARK, 2'd1, 1'b0, 1'b1);
        send_byte(9'h1a5);
        expect_byte(9'h1a5, 1'b0, 1'b0, 1'b0);

        // CTS must hold a queued frame until the peer is ready.
        cts_n = 1'b1;
        apply_config(4'd8, PARITY_NONE, 2'd1, 1'b1, 1'b1);
        send_byte(9'h0c6);
        repeat (80) begin
            @(negedge clk);
            if (tx_o !== 1'b1) begin
                $display("FAIL: TX started while CTS_N was deasserted");
                error_count = error_count + 1;
            end
        end
        cts_n = 1'b0;
        expect_byte(9'h0c6, 1'b0, 1'b0, 1'b0);

        // A sustained low line is reported once as a break frame.
        apply_config(4'd8, PARITY_NONE, 2'd1, 1'b0, 1'b1);
        tx_break = 1'b1;
        expect_byte(9'h000, 1'b0, 1'b1, 1'b1);
        tx_break = 1'b0;
        repeat (20) @(negedge clk);

        if (rx_overrun) begin
            $display("FAIL: unexpected RX FIFO overrun");
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("PASS: configurable UART self-check completed");
        else
            $display("FAIL: configurable UART self-check found %0d error(s)", error_count);

        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: global simulation timeout");
        $finish;
    end

endmodule
