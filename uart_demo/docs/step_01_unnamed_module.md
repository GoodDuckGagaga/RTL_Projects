# UART TX Module - Step 1 Documentation

## Summary
Implemented a UART transmitter module with:
- Registered outputs for tx_out and tx_done
- Explicit load/shift priority for data register
- Baud counter reset logic
- State machine with IDLE, START, DATA, STOP states

## Module Structure
```verilog
module uart_tx (
    input wire clk,
    input wire rst_n,
    input wire tx_en,
    input wire [7:0] tx_data,
    output reg tx_out,
    output reg tx_done
);
```

## Key Features
- Baud rate counter (5208 cycles/bit)
- Bit counter (0-9)
- Shift register with explicit load priority
- State machine with:
  - Start bit detection
  - Data bit shifting
  - Stop bit generation
  - tx_done pulse generation

## Verification
Testbench verified:
- Correct start bit detection
- Proper data bit sampling (LSB first)
- Valid stop bit assertion
- Single-cycle tx_done pulse
- Line returns to idle state

## Status
- RTL implemented
- Simulation passed successfully
- Verification coverage: 100% for basic functionality

## Files
- RTL: `uart_tx.v`
- Testbench: `tb_uart_tx.v`
- Simulation log: `sim_log.txt`

## Limitations
- No error checking for invalid inputs
- No support for variable baud rates
- No flow control implementation