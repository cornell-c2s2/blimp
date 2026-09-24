// Unconstrained formal environment for the ROB.
//
// `ins_*` represents completions arriving in arbitrary order.  There are no
// ordering assumptions: that is the behavior the ROB is intended to absorb.
module rob_formal_top #(
  parameter int p_depth    = 4,
  parameter int p_msg_bits = 8,
  parameter int p_entry_bits = $clog2(p_depth)
) (
  input logic clk,
  input logic rst,
  input logic [p_entry_bits-1:0] ins_idx,
  input logic [p_msg_bits-1:0]   ins_msg,
  input logic                    ins_en,
  input logic                    deq_en
);

  logic [p_entry_bits-1:0] deq_idx;
  logic [p_msg_bits-1:0]   deq_msg;
  logic                    deq_rdy;

  ROB #(
    .p_depth    (p_depth),
    .p_msg_bits (p_msg_bits)
  ) dut (.*);

endmodule
