module uart_tx (
    input wire clk,
    input wire rst_n,
    input wire tx_en,
    input wire [7:0] tx_data,
    output reg tx_out,
    output reg tx_done
);

    parameter IDLE  = 2'b00;
    parameter START = 2'b01;
    parameter DATA  = 2'b10;
    parameter STOP  = 2'b11;

    reg [1:0] state;
    reg [1:0] next_state;

    reg [12:0] baud_cnt;
    reg [3:0]  bit_cnt;
    reg [7:0]  shift_reg;

    wire bit_tick = (baud_cnt == 13'd5207);

    // FSM next state logic
    always @(*) begin
        case (state)
            IDLE:  next_state = tx_en ? START : IDLE;
            START: next_state = bit_tick ? DATA : START;
            DATA:  next_state = bit_tick ? (bit_cnt == 4'd8 ? STOP : DATA) : DATA;
            STOP:  next_state = bit_tick ? IDLE : STOP;
            default: next_state = IDLE;
        endcase
    end

    // FSM state register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else state <= next_state;
    end

    // Baud counter: counts 0 to 5207 (5208 cycles/bit)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) baud_cnt <= 13'd0;
        else if (state == IDLE && tx_en) baud_cnt <= 13'd0;
        else if (bit_tick) baud_cnt <= 13'd0;
        else if (state != IDLE) baud_cnt <= baud_cnt + 1'b1;
    end

    // Bit counter: tracks frame progress 0-9
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bit_cnt <= 4'd0;
        else if (state == IDLE && tx_en) bit_cnt <= 4'd0;
        else if (state == STOP && bit_tick) bit_cnt <= 4'd0;
        else if (bit_tick) bit_cnt <= bit_cnt + 1'b1;
    end

    // Shift register: explicit load priority over shift
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) shift_reg <= 8'd0;
        else if (state == IDLE && tx_en) shift_reg <= tx_data;
        else if (state == DATA && bit_tick) shift_reg <= shift_reg >> 1;
    end

    // Registered tx_out driven by current state
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tx_out <= 1'b1;
        else begin
            case (state)
                IDLE:  tx_out <= 1'b1;
                START: tx_out <= 1'b0;
                DATA:  tx_out <= shift_reg[0];
                STOP:  tx_out <= 1'b1;
                default: tx_out <= 1'b1;
            endcase
        end
    end

    // Registered tx_done: single-cycle pulse on STOP->IDLE transition
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) tx_done <= 1'b0;
        else tx_done <= (state == STOP && bit_tick);
    end

endmodule