# Run from this directory: jaspergold -batch -tcl run.tcl
clear -all

analyze -sv ../../hw/writeback_commit/ROB.v
analyze -sv rob_formal_top.sv
analyze -sv rob_assertions.sv

elaborate -top rob_formal_top
clock clk
reset rst

prove -all
check_cov -all
exit
