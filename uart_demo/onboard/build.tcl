#!/bin/bash
# Minimal Vivado build helper
# Usage: chmod +x build.sh && ./build.sh
# Requires Vivado in PATH

PROJ_DIR="uart_demo_build"
PART="xc7a35ticsg324-1L" # Replace with actual target FPGA part

mkdir -p "$PROJ_DIR"

cat > build.tcl << 'TCL_EOF'
create_project uart_demo ./uart_demo_build -part ${PART} -force
set_property target_language Verilog [current_project]

add_files -norecurse {
    rtl/unnamed_module.v
    rtl/uart_tx.v
    board_top.v
}
add_files -norecurse constraints.xdc

set_property top board_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Build complete. Bitstream: ./uart_demo_build/uart_demo_build.runs/impl_1/board_top.bit"
TCL_EOF

vivado -mode batch -source build.tcl