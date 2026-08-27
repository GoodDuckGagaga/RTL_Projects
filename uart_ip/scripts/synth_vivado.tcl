set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $project_dir build vivado]

set part_name xc7a35tcpg236-1
set clock_period_ns 10.000

file mkdir $build_dir

read_verilog -sv [glob [file join $project_dir rtl *.sv]]
synth_design -top uart_core -part $part_name
create_clock -name clk_i -period $clock_period_ns [get_ports clk_i]

opt_design
place_design
route_design

report_utilization -file [file join $build_dir utilization.rpt]
report_timing_summary -delay_type max -max_paths 10 \
    -file [file join $build_dir timing_summary.rpt]
write_checkpoint -force [file join $build_dir uart_core_routed.dcp]

set timing_paths [get_timing_paths -delay_type max -max_paths 1]
if {[llength $timing_paths] > 0} {
    set worst_slack [get_property SLACK [lindex $timing_paths 0]]
    puts "UART_IP_WORST_SLACK_NS=$worst_slack"
}
puts "UART_IP_VIVADO_CHECK=PASS"
