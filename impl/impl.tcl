
# RedWood EDA
# FPGA Implementation of WARP-V

#
#STEP#0: define your customized warpv top file 
#
# test is a 4-stage warpv with some edit in the result verilog file #wil be fixed in sandPiper then can be used with any design
set designfile risc-v_4-stage_retime
set design warp-v_risc-v_4-stage_retime
set cons warpv_constraints.xdc


#
# STEP#1: define output directory area.
#
set outputDir out/fpga_impl
file mkdir $outputDir

#
# STEP#2: setup design sources and constraints
#
read_verilog -sv ./out/$designfile/$design.sv
read_verilog  ../formal/verilog/clk_gate.v
read_verilog -sv ../formal/verilog/pseudo_rand.sv
set_property include_dirs {./out ../formal ../formal/verilog} [current_fileset]
read_xdc $cons

#
# STEP#3: run synthesis, report utilization and timing estimates, write checkpoint design
#
synth_design -top top -part xc7z020clg484-1 -retiming
file mkdir $outputDir/syn/reports
write_checkpoint -force $outputDir/syn/post_synth
report_timing_summary -file $outputDir/syn/reports/post_synth_timing_summary.rpt
report_power -file $outputDir/syn/reports/post_synth_power.rpt

#
# STEP#4: run placement and logic optimzation, report utilization and timing estimates, write checkpoint design
#
opt_design -directive ExploreArea
place_design
phys_opt_design
file mkdir $outputDir/place
file mkdir $outputDir/place/reports
write_checkpoint -force $outputDir/place/post_place
report_timing_summary -file $outputDir/place/reports/post_place_timing_summary.rpt

#
# STEP#5: run router, report actual utilization and timing, write checkpoint design, run drc, write verilog and xdc out
#
route_design
file mkdir $outputDir/route
file mkdir $outputDir/route/reports
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
		set fid [open out/fpga_impl/status.txt w]
		puts $fid "false" 
		close $fid
    } else {

    }
 }
close $timing_report
puts $met_timing


set search_util "Slice LUTs"
set util_report [open $outputDir/route/reports/post_route_util.rpt]
 while {[gets $util_report data] != -1} {
    if {[string match *[string toupper $search_util]* [string toupper $data]] } {
		set haha $data
    } else {
    }
 }
close $util_report
set theWords [regexp -all -inline {\S+} $haha]
puts $haha
puts [lindex $theWords 4]

set fid [open out/fpga_impl/FreqArea.txt a+]
puts $fid [lindex $theWords 4]
close $fid
exit
