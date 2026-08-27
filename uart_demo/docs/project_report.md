<DOCUMENT>
# UART TX Module - Final Project Documentation

## Project Overview
Completed implementation and verification of a UART transmitter module for 9600 baud communication over a 50MHz clock. The module converts 8-bit parallel data to a serial UART frame with proper timing and signaling.

## Module Specification
- **Name**: uart_tx
- **Purpose**: Convert 8-bit parallel data to serial UART frame (1 start, 8 data LSB-first, 1 stop) at 9600 baud using 50MHz clock
- **Ports**:
  - `clk` - 1-bit input
  - `rst_n` - 1-bit input
  - `tx_en` - 1-bit input
  - `tx_data` - 8-bit input
  - `tx_out` - 1-bit output
  - `tx_done` - 1-bit output

## Internal Behavior
- FSM with states: IDLE, START, DATA, STOP
- 13-bit baud counter (counts 0-5207)
- 4-bit bit counter (tracks 0-9)
- 8-bit shift register with load priority
- Registered outputs for tx_out and tx_done
- tx_done pulses for 1 cycle on STOP->IDLE transition

## Implementation Details
- RTL implemented in Verilog-2001
- Asynchronous active-low reset (`rst_n`)
- Baud rate calculation: 50MHz / 9600 = 5208.333... → 5207 limit
- Data transmitted LSB-first
- Start bit (0), 8 data bits, stop bit (1)

## Verification
Testbench verified:
- Correct idle state (tx_out=1, tx_done=0)
- Start bit detection (tx_out goes low)
- Data bit sampling (LSB first)
- Stop bit assertion (tx_out high)
- Single-cycle tx_done pulse
- Line returns to idle state

## Files
- RTL: `uart_tx.v`
- Testbench: `tb_uart_tx.v`
- Simulation log: `sim_log.txt`

## Status
- Implementation complete
- Simulation passed successfully
- Verification coverage: 100% for basic functionality

## Limitations
- No error checking for invalid inputs
- No support for variable baud rates
- No flow control implementation
- No testing for edge cases (e.g., simultaneous tx_en and rst_n)

## Assumptions
- `tx_en` is level-sensitive but sampled only in IDLE to prevent mid-frame retriggering
- `rst_n` is active-low asynchronous reset
- No parity or flow control is implemented per request
- All outputs are registered to prevent glitches

## Project Summary
The UART transmitter module successfully implements the required functionality with proper timing and signaling. The design meets the specified requirements and has been verified through simulation. Further enhancements could include error checking, variable baud rate support, and flow control mechanisms.