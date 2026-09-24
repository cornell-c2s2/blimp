// Assertions bound into ROB.  They intentionally make no assumptions about
// the order in which completion results (ins_*) arrive.
module rob_assertions #(
  parameter int p_depth      = 32,
  parameter int p_msg_bits   = 32,
  parameter int p_entry_bits = $clog2(p_depth)
) (
  input logic                    clk,
  input logic                    rst,
  input logic [p_entry_bits-1:0] ins_idx,
  input logic [p_msg_bits-1:0]   ins_msg,
  input logic                    ins_en,
  input logic [p_entry_bits-1:0] deq_idx,
  input logic [p_msg_bits-1:0]   deq_msg,
  input logic                    deq_en,
  input logic                    deq_rdy,
  input logic [p_entry_bits-1:0] deq_ptr,
  input logic                    head_val,
  input logic [p_msg_bits-1:0]   head_msg
);

  function automatic logic [p_entry_bits-1:0] next_idx(
    input logic [p_entry_bits-1:0] idx
  );
    if (idx == p_entry_bits'(p_depth - 1))
      next_idx = '0;
    else
      next_idx = idx + 1'b1;
  endfunction

  // A completion for the current head may be consumed immediately.  The
  // bypass must expose that exact index/message and declare it ready.
  ap_bypass_is_exact: assert property (@(posedge clk) disable iff (rst)
    ins_en && deq_en && (ins_idx == deq_ptr)
    |-> deq_rdy && (deq_idx == ins_idx) && (deq_msg == ins_msg));

  // Without a simultaneous head bypass, output is precisely the current
  // ROB-head entry.  This is the central in-order-commit invariant.
  ap_valid_head_is_visible: assert property (@(posedge clk) disable iff (rst)
    head_val && !(ins_en && deq_en && (ins_idx == deq_ptr))
    |-> deq_rdy && (deq_idx == deq_ptr) && (deq_msg == head_msg));

  // An empty head cannot be dequeued unless the arriving completion is for
  // that same head (the bypass case above).
  ap_empty_head_not_ready: assert property (@(posedge clk) disable iff (rst)
    !head_val && !(ins_en && (ins_idx == deq_ptr)) |-> !deq_rdy);

  // A dequeue handshake consumes exactly one program-order ROB position;
  // this includes the wrap from the final entry back to zero.
  ap_dequeue_advances_one: assert property (@(posedge clk) disable iff (rst)
    deq_en && deq_rdy |=> rst || (deq_ptr == next_idx($past(deq_ptr))));

  // In the absence of a dequeue handshake, the commit head is unchanged.
  ap_no_dequeue_holds_head: assert property (@(posedge clk) disable iff (rst)
    !(deq_en && deq_rdy) |=> rst || (deq_ptr == $past(deq_ptr)));

  // Reachability checks ensure the proof actually explores completion-order
  // inversion, head bypass, and pointer wraparound.
  cp_bypass: cover property (@(posedge clk) !rst ##1
    ins_en && deq_en && (ins_idx == deq_ptr));
  cp_out_of_order_completion: cover property (@(posedge clk) !rst ##1
    ins_en && (ins_idx != deq_ptr) ##1
    ins_en && (ins_idx == deq_ptr) && deq_en);
  cp_wraparound: cover property (@(posedge clk) !rst ##1
    deq_ptr == p_entry_bits'(p_depth - 1) && deq_en && deq_rdy ##1
    deq_ptr == '0);

endmodule

bind ROB rob_assertions #(
  .p_depth      (p_depth),
  .p_msg_bits   (p_msg_bits),
  .p_entry_bits (p_entry_bits)
) rob_assertions_i (
  .clk      (clk),
  .rst      (rst),
  .ins_idx  (ins_idx),
  .ins_msg  (ins_msg),
  .ins_en   (ins_en),
  .deq_idx  (deq_idx),
  .deq_msg  (deq_msg),
  .deq_en   (deq_en),
  .deq_rdy  (deq_rdy),
  .deq_ptr  (deq_ptr),
  .head_val (entries[deq_ptr].val),
  .head_msg (entries[deq_ptr].msg)
);
