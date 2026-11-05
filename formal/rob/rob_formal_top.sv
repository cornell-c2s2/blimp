// Formal environment for the ROB.
//
// `ins_*` represents completions arriving in arbitrary order.  There are no
// ordering assumptions: that is the behavior the ROB is intended to absorb.
// The scoreboard documents index-range and optional producer assumptions.
module rob_formal_top #(
  parameter int p_depth    = 32,
  parameter int p_msg_bits = 76,
  parameter int p_entry_bits = $clog2(p_depth),
  parameter bit p_legal_traffic = 1'b1
) (
  input logic clk,
  input logic rst,
  input logic [p_entry_bits-1:0] ins_idx,
  input logic [p_msg_bits-1:0]   ins_msg,
  input logic                    ins_en,
  input logic                    deq_en,
  input logic [p_entry_bits-1:0] watch_idx
);

  logic [p_entry_bits-1:0] deq_idx;
  logic [p_msg_bits-1:0]   deq_msg;
  logic                    deq_rdy;

  ROB #(
    .p_depth    (p_depth),
    .p_msg_bits (p_msg_bits)
  ) dut (.*);

  rob_scoreboard #(
    .p_depth (p_depth),
    .p_msg_bits (p_msg_bits),
    .p_legal_traffic (p_legal_traffic)
  ) scoreboard (.*);

  // Check storage against the independently updated reference model. These
  // assertions are inductive lemmas for the port-level payload proof, and also
  // detect lost/corrupt completions while an older instruction blocks dequeue.
  // DUT state is observed here only; it never drives the reference model.
  ap_watched_pending_matches: assert property (@(posedge clk) disable iff (rst)
    dut.entries[watch_idx].val == scoreboard.pending[watch_idx]);

  ap_watched_storage_matches: assert property (@(posedge clk) disable iff (rst)
    scoreboard.pending[watch_idx]
    |-> dut.entries[watch_idx].msg == scoreboard.watched_payload);

endmodule
