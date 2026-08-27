# Generic XDC Template - Replace <PLACEHOLDER> values with target board specifics
# Clock: 50 MHz (Period = 20.000 ns)
set_property PACKAGE_PIN <CLK_PIN> [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 20.000 -name sys_clk [get_ports clk]

# Reset: Active-low asynchronous
set_property PACKAGE_PIN <RST_PIN> [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# UART TX Output
set_property PACKAGE_PIN <UART_TX_PIN> [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# Control & Data Inputs
set_property PACKAGE_PIN <TX_EN_PIN> [get_ports tx_en]
set_property IOSTANDARD LVCMOS33 [get_ports tx_en]

set_property PACKAGE_PIN <DATA_PIN_0> [get_ports {tx_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx_data[0]}]
set_property PACKAGE_PIN <DATA_PIN_1> [get_ports {tx_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx_data[1]}]
set_property PACKAGE_PIN <DATA_PIN_2> [get_ports {tx_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx_data[2]}]
set_property PACKAGE_PIN <DATA_PIN_3> [get_ports {tx_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx_data[3]}]
set_property PACKAGE_PIN <DATA_PIN_4> [get_ports {tx_data[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx_data[4]}]
set_property PACKAGE_PIN <DATA_PIN_5> [get_ports {tx_data[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx_data[5]}]
set_property PACKAGE_PIN <DATA_PIN_6> [get_ports {tx_data[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx_data[6]}]
set_property PACKAGE_PIN <DATA_PIN_7> [get_ports {tx_data[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {tx_data[7]}]