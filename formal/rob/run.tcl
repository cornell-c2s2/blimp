# Run from this directory: jaspergold -batch -tcl run.tcl
clear -all

analyze -sv +define+FORMAL ../../hw/writeback_commit/ROB.v
analyze -sv rob_formal_top.sv
analyze -sv rob_assertions.sv

elaborate -top rob_formal_top
clock clk
reset rst

prove -all
# Covers are discharged by prove -all.
exit
