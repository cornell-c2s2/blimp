//========================================================================
// ExQueue.v
//========================================================================
// A queue to buffer outputs of execute units
//
// A squash marks buffered entries younger than the squash as killed at the
// clock edge; a killed entry at the head is dropped without being sent.
// The bypass path (empty queue) is not filtered: the commit unit drops a
// squashed instruction that arrives in the squash cycle. out.val never
// depends on this cycle's squash, which would form a combinational loop

`ifndef HW_EXECUTE_EXQUEUE_V
`define HW_EXECUTE_EXQUEUE_V

`include "hw/util/SeqAge.v"
`include "intf/CommitNotif.v"
`include "intf/SquashNotif.v"
`include "intf/X__WIntf.v"

module ExQueue #(
  parameter p_depth = 8
)(
  input  logic clk,
  input  logic rst,

  X__WIntf.W_intf in,
  X__WIntf.X_intf out,

  //----------------------------------------------------------------------
  // Squash and commit (age reference)
  //----------------------------------------------------------------------

  SquashNotif.sub squash,
  CommitNotif.sub commit
);

  localparam p_seq_num_bits   = in.p_seq_num_bits;
  localparam p_phys_addr_bits = in.p_phys_addr_bits;

  //----------------------------------------------------------------------
  // Define message type, connect to interfaces
  //----------------------------------------------------------------------

  typedef struct packed {
    logic                 [31:0] pc;
    logic                  [4:0] waddr;
    logic                 [31:0] wdata;
    logic                        wen;
    logic   [p_seq_num_bits-1:0] seq_num;
    logic [p_phys_addr_bits-1:0] preg;
    logic [p_phys_addr_bits-1:0] ppreg;
    logic                  [2:0] csr_cmd;
    logic                 [11:0] csr_addr;
    logic                 [31:0] csr_wdata;
    logic                        exc_val;
    logic                  [4:0] exc_cause;
    logic                 [31:0] exc_tval;
    logic                        redirect;
    logic                 [31:0] redirect_target;
  } msg_t;

  msg_t in_msg;
  msg_t out_msg;

  assign in_msg.pc      = in.pc;
  assign in_msg.waddr   = in.waddr;
  assign in_msg.wdata   = in.wdata;
  assign in_msg.wen     = in.wen;
  assign in_msg.seq_num = in.seq_num;
  assign in_msg.preg    = in.preg;
  assign in_msg.ppreg   = in.ppreg;
  assign in_msg.csr_cmd   = in.csr_cmd;
  assign in_msg.csr_addr  = in.csr_addr;
  assign in_msg.csr_wdata = in.csr_wdata;
  assign in_msg.exc_val   = in.exc_val;
  assign in_msg.exc_cause = in.exc_cause;
  assign in_msg.exc_tval  = in.exc_tval;
  assign in_msg.redirect = in.redirect;
  assign in_msg.redirect_target = in.redirect_target;

  assign out.pc      = out_msg.pc;
  assign out.waddr   = out_msg.waddr;
  assign out.wdata   = out_msg.wdata;
  assign out.wen     = out_msg.wen;
  assign out.seq_num = out_msg.seq_num;
  assign out.preg    = out_msg.preg;
  assign out.ppreg   = out_msg.ppreg;
  assign out.csr_cmd   = out_msg.csr_cmd;
  assign out.csr_addr  = out_msg.csr_addr;
  assign out.csr_wdata = out_msg.csr_wdata;
  assign out.exc_val   = out_msg.exc_val;
  assign out.exc_cause = out_msg.exc_cause;
  assign out.exc_tval  = out_msg.exc_tval;
  assign out.redirect = out_msg.redirect;
  assign out.redirect_target = out_msg.redirect_target;

  //----------------------------------------------------------------------
  // Buffer with bypassing, and a killed bit per entry
  //----------------------------------------------------------------------

  localparam p_ptr_bits = ( p_depth > 1 ) ? $clog2( p_depth ) : 1;
  localparam p_cnt_bits = $clog2( p_depth + 1 );

  msg_t buffer_msg    [p_depth];
  logic buffer_killed [p_depth];

  logic [p_ptr_bits-1:0] head;
  logic [p_ptr_bits-1:0] tail;
  logic [p_cnt_bits-1:0] count;

  logic buffer_push;
  logic buffer_pop;
  logic buffer_empty;
  logic buffer_full;
  logic head_killed;

  assign buffer_empty = ( count == '0 );
  assign buffer_full  = ( int'(count) == p_depth );
  assign head_killed  = !buffer_empty & buffer_killed[head];

  logic can_bypass;
  assign can_bypass = buffer_empty;

  //----------------------------------------------------------------------
  // Squashing
  //----------------------------------------------------------------------

  SeqAge seq_age (
    .clk    (clk),
    .rst    (rst),
    .commit (commit)
  );

  logic [31:0] unused_squash_target;
  assign unused_squash_target = squash.target;

  // Whether buffer slot i holds an entry
  function automatic logic occupied( input int i );
    int offset;
    offset = i - int'(head);
    if( offset < 0 )
      offset = offset + p_depth;
    return ( offset < int'(count) );
  endfunction

  always_ff @( posedge clk ) begin
    if( rst ) begin
      head  <= '0;
      tail  <= '0;
      count <= '0;
      for( int i = 0; i < p_depth; i = i + 1 ) begin
        buffer_msg[i]    <= '0;
        buffer_killed[i] <= 1'b0;
      end
    end else begin
      // Kill buffered entries younger than the squash
      for( int i = 0; i < p_depth; i = i + 1 ) begin
        if( occupied( i ) & squash.val &
            seq_age.is_older( squash.seq_num, buffer_msg[i].seq_num ) )
          buffer_killed[i] <= 1'b1;
      end

      if( buffer_pop )
        head <= ( int'(head) == p_depth - 1 ) ? '0 : head + 1;

      // Push (after the kill loop: a full queue's push reuses the slot
      // freed by a same-cycle pop, and its write wins)
      if( buffer_push ) begin
        buffer_msg[tail]    <= in_msg;
        buffer_killed[tail] <= squash.val &
                               seq_age.is_older( squash.seq_num, in_msg.seq_num );
        tail <= ( int'(tail) == p_depth - 1 ) ? '0 : tail + 1;
      end

      if( buffer_push & !buffer_pop )
        count <= count + 1;
      else if( !buffer_push & buffer_pop )
        count <= count - 1;
    end
  end

  //----------------------------------------------------------------------
  // Pass messages
  //----------------------------------------------------------------------

  always_comb begin
    if( can_bypass )
      out_msg = in_msg;
    else
      out_msg = buffer_msg[head];
  end

  //----------------------------------------------------------------------
  // Control signals
  //----------------------------------------------------------------------
  // A killed head is popped without being sent, which also frees a slot

  assign in.rdy  = !buffer_full | out.rdy | head_killed;
  assign out.val = ( !buffer_empty & !head_killed ) | ( buffer_empty & in.val );

  assign buffer_push = in.rdy & in.val & !( can_bypass & out.rdy );
  assign buffer_pop  = !buffer_empty & ( out.rdy | head_killed );
endmodule

`endif // HW_EXECUTE_EXQUEUE_V
