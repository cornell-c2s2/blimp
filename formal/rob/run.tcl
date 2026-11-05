# Run from this directory: jaspergold -batch -tcl run.tcl
# Optional environment: ROB_DEPTH, ROB_MSG_BITS, ROB_LEGAL_TRAFFIC,
# ROB_RTL (for isolated mutations), ROB_REPORT (text results destination),
# ROB_JSON (machine-readable results destination).
clear -all
# Jasper's -tcl command interpreter does not populate Tcl's [info script].
set script_dir [pwd]
set rtl [file normalize [file join $script_dir ../../hw/writeback_commit/ROB.v]]
set depth 32
set msg_bits 76
set legal 1
if {[info exists ::env(ROB_DEPTH)]} { set depth $::env(ROB_DEPTH) }
if {[info exists ::env(ROB_MSG_BITS)]} { set msg_bits $::env(ROB_MSG_BITS) }
if {[info exists ::env(ROB_LEGAL_TRAFFIC)]} { set legal $::env(ROB_LEGAL_TRAFFIC) }
if {[info exists ::env(ROB_RTL)]} { set rtl [file normalize $::env(ROB_RTL)] }
if {![string is integer -strict $depth] || $depth < 2 ||
    ![string is integer -strict $msg_bits] || $msg_bits < 1 ||
    $legal ni {0 1}} {
  error "Require ROB_DEPTH >= 2, ROB_MSG_BITS >= 1, ROB_LEGAL_TRAFFIC in {0 1}"
}
puts "ROB configuration: depth=$depth msg_bits=$msg_bits legal_traffic=$legal rtl=$rtl"

analyze -sv +define+FORMAL+SYNTHESIS $rtl
analyze -sv [file join $script_dir rob_scoreboard.sv]
analyze -sv [file join $script_dir rob_formal_top.sv]
analyze -sv [file join $script_dir rob_assertions.sv]

# Keep all DUT/model storage concrete, regardless of array thresholds.
elaborate -top rob_formal_top -disable_auto_bbox -parameter p_depth $depth -parameter p_msg_bits $msg_bits -parameter p_legal_traffic $legal
clock clk
reset rst
set abstractions [get_design_info -list bbox_inst stopat undriven_internal -silent]
if {[llength $abstractions]} { error "Unexpected black boxes/undriven state: $abstractions" }
set_prove_time_limit 120s

prove -all
report -all
if {[info exists ::env(ROB_REPORT)]} {
  report -all -file $::env(ROB_REPORT) -force
}
if {[info exists ::env(ROB_JSON)]} {
  report -json -file $::env(ROB_JSON) -force
}
# Do not treat successful Tcl execution as successful verification. Reject
# failed/unresolved assertions and unreachable/unresolved scenario covers.
set bad_assertions [get_property_list -include {type assert} -exclude {status proven}]
set bad_covers [get_property_list -include {type cover} -exclude {status covered}]
if {[llength [get_property_list -include {type assert}]] != 11} {
  error "Expected all eleven ROB assertions to be present"
}
if {[llength $bad_assertions] || [llength $bad_covers]} {
  error "ROB formal failed: assertions=$bad_assertions covers=$bad_covers"
}
exit
