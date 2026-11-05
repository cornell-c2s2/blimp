// Independent, port-only model of completions waiting for in-order retirement.
// Nothing in the model is read from DUT entries, its pointer, or its readiness.
module rob_scoreboard #(
  parameter int p_depth = 4,
  parameter int p_msg_bits = 8,
  parameter int p_entry_bits = $clog2(p_depth),
  parameter bit p_legal_traffic = 1'b1
) (
  input logic clk, rst,
  input logic [p_entry_bits-1:0] ins_idx,
  input logic [p_msg_bits-1:0] ins_msg,
  input logic ins_en, deq_en,
  input logic [p_entry_bits-1:0] deq_idx,
  input logic [p_msg_bits-1:0] deq_msg,
  input logic deq_rdy,
  input logic [p_entry_bits-1:0] watch_idx
);
  logic [p_depth-1:0] pending;
  // Universally quantify over an arbitrary fixed slot. Tracking one payload
  // instead of duplicating every DUT payload makes the larger proof tractable.
  // The DUT's entire storage remains concrete: nothing is blackboxed.
  logic [p_msg_bits-1:0] watched_payload;
  // An integer counter avoids relying on the DUT's truncated pointer width.
  // Use addition/comparison rather than %, which Jasper 2024.09 automatically
  // abstracts for non-power-of-two divisors.
  int unsigned head;
  logic arriving_head, expected_ready, expected_pop;
  logic [p_msg_bits-1:0] expected_payload;
  logic [1:0] wraps;

  assign arriving_head = ins_en && (int'(ins_idx) == head);
  assign expected_ready = pending[head] || arriving_head;
  assign expected_pop = deq_en && expected_ready;
  assign expected_payload = arriving_head ? ins_msg : watched_payload;

  // These constrain a verification selector, not the ROB's input traffic.
  as_watch_in_range: assume property (@(posedge clk) disable iff (rst)
    int'(watch_idx) < p_depth);
  as_watch_constant: assume property (@(posedge clk) disable iff (rst)
    1'b1 |=> $stable(watch_idx));

  // There is no insert-ready port: each enabled insertion is accepted.
  // Only a valid index is required in unrestricted mode. Non-power-of-two
  // configurations have unused binary encodings that are outside the API.
  as_index_in_range: assume property (@(posedge clk) disable iff (rst)
    ins_en |-> int'(ins_idx) < p_depth);

  if (p_legal_traffic) begin : LEGAL_TRAFFIC
    // This is a producer promise, expressed using reference state only.
    // Reusing a slot after it retires remains legal (including across wrap).
    // No assumptions constrain dequeue enable or completion arrival order.
    as_no_pending_overwrite: assume property (@(posedge clk) disable iff (rst)
      ins_en |-> !pending[ins_idx]);
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      head <= 0;
      pending <= '0;
      wraps <= '0;
      watched_payload <= '0;
    end else begin
      // Record a completion even when the consumer is stalled. In unrestricted
      // mode duplicate indices have the RTL's last-writer-wins semantics.
      for (int i = 0; i < p_depth; i++) begin
        if (ins_en && (int'(ins_idx) == i)) begin
          pending[i] <= 1'b1;
        end
        // A consumed completion must not survive the next trip around the ROB.
        if (expected_pop && (head == i)) pending[i] <= 1'b0;
      end
      if (ins_en && (ins_idx == watch_idx)) watched_payload <= ins_msg;
      if (expected_pop) begin
        head <= (head + 1 == p_depth) ? 0 : head + 1;
        if ((head == p_depth - 1) && (wraps != 2)) wraps <= wraps + 1'b1;
      end
    end
  end

  // Complete readiness equation, including arrival at an empty head when
  // deq_en=0. This avoids assuming the consumer will request a dequeue.
  ap_ready_matches_model: assert property (@(posedge clk) disable iff (rst)
    deq_rdy == expected_ready);

  ap_index_matches_model: assert property (@(posedge clk) disable iff (rst)
    int'(deq_idx) == head);

  // Compare the output against the originally inserted message, never the
  // DUT's own message storage. All payload bits remain symbolic.
  ap_payload_matches_model: assert property (@(posedge clk) disable iff (rst)
    expected_pop && (head == int'(watch_idx))
    |-> deq_rdy && (deq_msg == expected_payload));

  ap_no_phantom_dequeue: assert property (@(posedge clk) disable iff (rst)
    deq_en && deq_rdy |-> pending[head] || arriving_head);

  cp_head_arrives_while_stalled: cover property (@(posedge clk) disable iff (rst)
    !pending[head] && arriving_head && !deq_en ##1
    pending[head] && deq_en && !ins_en && deq_rdy);

  cp_stored_head_survives_stall: cover property (@(posedge clk) disable iff (rst)
    pending[head] && !deq_en && !arriving_head [*3] ##1
    expected_pop && !arriving_head);

  cp_insert_and_retire_different_slots: cover property (@(posedge clk) disable iff (rst)
    expected_pop && ins_en && !arriving_head);

  cp_fill_then_drain: cover property (@(posedge clk) disable iff (rst)
    (&pending) ##1 (!ins_en && expected_pop)[*p_depth] ##1
    (pending == '0) && !ins_en && !deq_rdy);

  cp_two_wraps_then_empty: cover property (@(posedge clk) disable iff (rst)
    (wraps == 2) && (pending == '0) && !ins_en && !deq_rdy);
endmodule
