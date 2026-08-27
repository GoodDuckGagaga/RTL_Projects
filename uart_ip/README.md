# Configurable UART IP

`uart_core` is a single-clock, full-duplex UART intended for FPGA reuse. It
supports runtime frame configuration, buffered ready/valid data paths, error
reporting, hardware flow control, loopback, break signalling, and an RS-485
driver-enable output.

## Main capabilities

- 5 to 9 data bits
- no, even, odd, mark, or space parity
- one or two stop bits
- compile-time 8x or 16x RX oversampling with three-sample majority voting
- runtime baud divisor update at an idle boundary
- independent parameterized TX and RX FIFOs
- active-low CTS/RTS hardware flow control
- internal digital loopback
- TX break generation and RX break detection
- per-entry parity, framing, and break status
- sticky RX overrun status with explicit clear
- `tx_de_o` for RS-485/half-duplex transceivers

The detailed architecture, configuration rules, timing strategy, and
integration guidance are in [docs/design.md](docs/design.md).

## Directory layout

```text
uart_ip/
  rtl/                 Synthesizable SystemVerilog
  tb/                  Self-checking testbench
  scripts/             Icarus and Vivado batch scripts
  docs/design.md       Design proposal and integration guide
  filelist.f           Simulation source list
```

## Quick simulation

From the `uart_ip` directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_iverilog.ps1
```

The self-check covers 8E1, 7O2, 9-bit mark parity, CTS throttling, internal and
pin-level loopback, and break detection.

## Vivado 2018.3 implementation check

The supplied script targets a generic Artix-7 `xc7a35tcpg236-1` and a 100 MHz
clock. Change `part_name` and `clock_period_ns` in the script for the real
device and constraint set.

```powershell
& 'D:\vivado18\Vivado\2018.3\bin\vivado.bat' -mode batch `
  -source .\scripts\synth_vivado.tcl
```

Reference result with Vivado 2018.3, `xc7a35tcpg236-1`, default IP parameters,
and a 100 MHz clock: 227 LUTs, 177 flip-flops, 16 LUTRAM cells, and
`+1.798 ns` worst setup slack after routing. This is a reproducibility check,
not a substitute for timing sign-off with the final part, pinout, and XDC.

## Configuration encoding

| Field | Encoding |
|---|---|
| `cfg_data_bits_i` | 5 through 9; out-of-range values are clamped |
| `cfg_parity_i` | 0 none, 1 even, 2 odd, 3 mark, 4 space |
| `cfg_stop_bits_i` | 2 selects two stops; every other value selects one |
| `cfg_baud_divisor_i` | clocks per oversample tick; minimum value is 2 |

Apply a configuration by asserting `cfg_valid_i` while `cfg_ready_o` is high.
The request is acknowledged for one cycle by `cfg_applied_o`.

The integer divisor is:

```text
round(CLK_HZ / (baud_rate * OVERSAMPLE))
```

and the resulting baud rate is:

```text
CLK_HZ / (cfg_baud_divisor_i * OVERSAMPLE)
```
