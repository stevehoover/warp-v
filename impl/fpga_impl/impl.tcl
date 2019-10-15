
# RedWood EDA
# FPGA Implementation of WARP-V

#
#STEP#0: define your customized warpv top file 
#
# test is a 4-stage warpv with some edit in the result verilog file #wil be fixed in sandPiper then can be used with any design
set design test
set cons warpv_constraints.xdc


#
# STEP#1: define output directory area.
#
set outputDir fpga_impl
file mkdir $outputDir

#
# STEP#2: setup design sources and constraints
#
read_verilog -sv ./out/$design/$design.sv
set_property include_dirs {./out} [current_fileset]
read_xdc fpga_impl/$cons

#
# STEP#3: run synthesis, report utilization and timing estimates, write checkpoint design
#
synth_design -top top -part xc7z020clg484-1
write_checkpoint -force $outputDir/post_synth
report_timing_summary -file $outputDir/syn/reports/post_synth_timing_summary.rpt
report_power -file $outputDir/syn/reports/post_synth_power.rpt

#
# STEP#4: run placement and logic optimzation, report utilization and timing estimates, write checkpoint design
#
opt_design
place_design
phys_opt_design
write_checkpoint -force $outputDir/place/post_place
report_timing_summary -file $outputDir/place/reports/post_place_timing_summary.rpt

#
# STEP#5: run router, report actual utilization and timing, write checkpoint design, run drc, write verilog and xdc out
#
route_design
write_checkpoint -force $outputDir/route/post_route
report_timing_summary -file $outputDir/route/reports/post_route_timing_summary.rpt
report_timing -sort_by group -max_paths 100 -path_type summary -file 	$outputDir/route/reports/post_route_timing.rpt
report_clock_utilization -file $outputDir/route/reports/clock_util.rpt
report_utilization -file $outputDir/route/reports/post_route_util.rpt
report_power -file $outputDir/route/reports/post_route_power.rpt
report_drc -file $outputDir/route/reports/post_imp_drc.rpt
write_verilog -force $outputDir/fpga_impl_netlist.v
write_xdc -no_fixed_only -force $outputDir/fpga_impl.xdc

#
# STEP#6: generate a bitstream
#
#write_bitstream -force $outputDir/bft.bit

#
#STEP#7: Printing Summary
#
set met_timing "Met Timing Constrains: true"
set search "Timing constraints are not met."
set timing_report [open $outputDir/route/reports/post_route_timing_summary.rpt]
 while {[gets $timing_report data] != -1} {
    if {[string match *[string toupper $search]* [string toupper $data]] } {
		set met_timing "Met Timing Constrains: false"
    } else {

    }
 }
close $timing_report
puts $met_timing
