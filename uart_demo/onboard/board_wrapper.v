// board_top.v - Thin adapter for generic board bring-up
// Verifies port mapping against unnamed_module.v
`timescale 1ns / 1ps

module board_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tx_en,
    input  wire  [7:0] tx_data,
    output wire        uart_tx
);

    // Instantiate the project top-level
    // Adjust port names if unnamed_module.v uses different identifiers
    unnamed_module u_top (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_en    (tx_en),
        .tx_data  (tx_data),
        .uart_tx  (uart_tx)
    );

endmodule