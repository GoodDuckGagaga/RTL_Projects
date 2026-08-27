`timescale 1ns/1ps
module tb_uart_tx;
    reg clk;
    reg rst_n;
    reg tx_en;
    reg [7:0] tx_data;
    wire tx_out;
    wire tx_done;

    uart_tx dut (
        .clk(clk),
        .rst_n(rst_n),
        .tx_en(tx_en),
        .tx_data(tx_data),
        .tx_out(tx_out),
        .tx_done(tx_done)
    );

    initial clk = 0;
    always #10 clk = ~clk; // 50MHz clock

    integer bit_period = 5208;
    integer half_bit   = 2604;
    reg [7:0] captured_data;
    integer i;

    initial begin

        $dumpfile("uart_tx.vcd");   // 指定生成的波形文件名
        $dumpvars(0, tb_uart_tx);   // 记录当前模块(tb_uart_tx)及其下层所有信号的波形

        rst_n = 0;
        tx_en = 0;
        tx_data = 8'hA5; // 1010_0101 -> LSB first: 1,0,1,0,0,1,0,1
        #100;
        rst_n = 1;
        #50;

        // Verify idle state
        if (tx_out !== 1'b1 || tx_done !== 1'b0) begin
            $display("FAIL: Incorrect idle state");
            $finish;
        end

        // Trigger transmission
        @(posedge clk);
        tx_en = 1;
        @(posedge clk);
        tx_en = 0;

        // Wait for registered start bit (tx_out goes low)
        while (tx_out !== 1'b0) @(posedge clk);
        @(posedge clk); // Sync to edge after detection

        // Wait 1.5 bit periods to land in the middle of the first data bit
        // This naturally absorbs the 1-cycle registered output delay
        repeat(bit_period + half_bit) @(posedge clk);

        // Sample 8 data bits at mid-bit intervals
        captured_data = 0;
        for (i=0; i<8; i=i+1) begin
            captured_data[i] = tx_out;
            repeat(bit_period) @(posedge clk);
        end

        // Verify stop bit is high
        if (tx_out !== 1'b1) begin
            $display("FAIL: Stop bit incorrect. tx_out=%b", tx_out);
            $finish;
        end

        // Wait for tx_done pulse
        while (tx_done !== 1'b1) @(posedge clk);
        @(posedge clk); // Advance to next cycle to verify pulse width
        // Spec requires exactly 1 cycle pulse
        if (tx_done !== 1'b0) begin
            $display("FAIL: tx_done pulse width > 1 cycle (spec requires single-cycle pulse)");
            $finish;
        end

        // Verify captured data matches transmitted data
        if (captured_data !== tx_data) begin
            $display("FAIL: Data mismatch. Expected %h, Got %h", tx_data, captured_data);
            $finish;
        end

        // Verify line returns to idle
        if (tx_out !== 1'b1) begin
            $display("FAIL: Line not idle after transmission");
            $finish;
        end

        $display("PASS: UART TX verification successful");
        $finish;
    end
endmodule