//========================================================================
// StoreQueue.v
//========================================================================
// Holds speculative (uncommitted) stores in program order.
//
//  - Allocate: decode reserves the tail entry when a store issues
//  - Fill:     the load-store unit writes the store's word address, byte
//              lanes and lane-aligned data
//  - Search:   per byte lane, the youngest filled entry for a word
//  - Dequeue:  the head is removed when its store commits
//  - Squash:   entries younger than the squashing instruction are removed
//
// Assumption: every filled entry is older than any load that searches,
// and every unfilled entry is younger. This holds because all loads and
// stores go through one in-order load-store unit, and a store fills in
// the cycle it leaves stage 1.
//
// See STORE_QUEUE_DESIGN.md.

`ifndef HW_WRITEBACK_STORE_QUEUE_V
`define HW_WRITEBACK_STORE_QUEUE_V

`include "hw/util/SeqAge.v"
`include "hw/writeback_commit/StoreBufferSearch.v"
`include "intf/CommitNotif.v"
`include "intf/SquashNotif.v"
`include "intf/StoreQueueIntf.v"

module StoreQueue #(
  parameter p_depth        = 4,
  parameter p_seq_num_bits = 5,
  parameter p_idx_bits     = ( p_depth > 1 ) ? $clog2( p_depth ) : 1
)(
  input  logic clk,
  input  logic rst,

  //----------------------------------------------------------------------
  // Allocate, fill and search
  //----------------------------------------------------------------------

  StoreQueueIntf.SQ_intf sq,

  //----------------------------------------------------------------------
  // Squash
  //----------------------------------------------------------------------

  SquashNotif.sub squash,

  //----------------------------------------------------------------------
  // Commit (age reference for squashes)
  //----------------------------------------------------------------------

  CommitNotif.sub commit,

  //----------------------------------------------------------------------
  // Dequeue
  //----------------------------------------------------------------------

  input  logic                      deq_en,
  output logic                      deq_rdy,
  output logic [p_seq_num_bits-1:0] deq_seq_num,
  output logic               [31:2] deq_addr,
  output logic                [3:0] deq_strb,
  output logic               [31:0] deq_data
);

  //----------------------------------------------------------------------
  // Parameter checks
  //----------------------------------------------------------------------

  generate
    if( sq.p_seq_num_bits != p_seq_num_bits ) begin: BAD_SEQ_NUM_BITS
      $error( "StoreQueue: p_seq_num_bits does not match StoreQueueIntf" );
    end
    if( sq.p_sq_idx_bits != p_idx_bits ) begin: BAD_IDX_BITS
      $error( "StoreQueue: StoreQueueIntf p_sq_idx_bits must be $clog2(p_depth)" );
    end
  endgenerate

  //----------------------------------------------------------------------
  // State
  //----------------------------------------------------------------------

  logic                      val     [p_depth];
  logic                      filled  [p_depth];
  logic [p_seq_num_bits-1:0] seq_num [p_depth];
  logic               [31:2] addr    [p_depth];
  logic                [3:0] strb    [p_depth];
  logic               [31:0] data    [p_depth];

  logic [p_idx_bits-1:0] head;
  logic [p_idx_bits-1:0] tail;

  logic full;
  assign full = val[tail];

  function automatic logic [p_idx_bits-1:0] incr( input logic [p_idx_bits-1:0] ptr );
    if( int'(ptr) == p_depth - 1 )
      return '0;
    else
      return ptr + 1;
  endfunction

  //----------------------------------------------------------------------
  // Squash
  //----------------------------------------------------------------------
  // Squashed entries are a contiguous youngest suffix, so the new tail is
  // head + (number of surviving entries)

  SeqAge seq_age (
    .*
  );

  logic                  removed [p_depth];
  logic [p_idx_bits-1:0] squash_tail;

  always_comb begin
    int num_survive;
    int new_tail;

    num_survive = 0;
    for( int i = 0; i < p_depth; i = i + 1 ) begin
      removed[i] = squash.val & val[i] &
                   seq_age.is_older( squash.seq_num, seq_num[i] );
      if( val[i] & !removed[i] )
        num_survive = num_survive + 1;
    end

    new_tail = int'(head) + num_survive;
    if( new_tail >= p_depth )
      new_tail = new_tail - p_depth;
    squash_tail = p_idx_bits'(new_tail);
  end

  //----------------------------------------------------------------------
  // Allocate, fill and dequeue
  //----------------------------------------------------------------------

  logic deq_xfer;
  logic alloc_xfer;
  logic fill_xfer;

  assign deq_rdy   = val[head] & filled[head];
  assign deq_xfer  = deq_en & deq_rdy;

  // Bypass: a slot freed by a dequeue is usable in the same cycle
  assign sq.alloc_rdy = !full | deq_xfer;
  assign sq.alloc_idx = tail;

  // A squash drops a same-cycle allocation and fills of removed entries
  assign alloc_xfer = sq.alloc_val & sq.alloc_rdy & !squash.val;
  assign fill_xfer  = sq.fill_val & val[sq.fill_idx] & !removed[sq.fill_idx];

  always_ff @( posedge clk ) begin
    if( rst ) begin
      head <= '0;
      tail <= '0;
      for( int i = 0; i < p_depth; i = i + 1 ) begin
        val[i]     <= 1'b0;
        filled[i]  <= 1'b0;
        seq_num[i] <= '0;
        addr[i]    <= '0;
        strb[i]    <= '0;
        data[i]    <= '0;
      end
    end else begin
      // Squash
      for( int i = 0; i < p_depth; i = i + 1 ) begin
        if( removed[i] )
          val[i] <= 1'b0;
      end

      // Fill
      if( fill_xfer ) begin
        filled[sq.fill_idx] <= 1'b1;
        addr[sq.fill_idx]   <= sq.fill_addr;
        strb[sq.fill_idx]   <= sq.fill_strb;
        data[sq.fill_idx]   <= sq.fill_data;
      end

      // Dequeue
      if( deq_xfer ) begin
        val[head] <= 1'b0;
        head      <= incr( head );
      end

      // Allocate (after dequeue: when full, the allocation reuses the
      // slot freed by the dequeue, and its write wins)
      if( alloc_xfer ) begin
        val[tail]     <= 1'b1;
        filled[tail]  <= 1'b0;
        seq_num[tail] <= sq.alloc_seq_num;
      end

      // Tail
      if( squash.val )
        tail <= squash_tail;
      else if( alloc_xfer )
        tail <= incr( tail );
    end
  end

  //----------------------------------------------------------------------
  // Dequeue outputs
  //----------------------------------------------------------------------

  assign deq_seq_num = seq_num[head];
  assign deq_addr    = addr[head];
  assign deq_strb    = strb[head];
  assign deq_data    = data[head];

  //----------------------------------------------------------------------
  // Search
  //----------------------------------------------------------------------

  logic eligible [p_depth];

  always_comb begin
    for( int i = 0; i < p_depth; i = i + 1 )
      eligible[i] = val[i] & filled[i];
  end

  StoreBufferSearch #(
    .p_depth    (p_depth),
    .p_ptr_bits (p_idx_bits)
  ) search (
    .eligible    (eligible),
    .addr        (addr),
    .strb        (strb),
    .data        (data),
    .tail        (tail),
    .search_addr (sq.search_addr),
    .hit         (sq.search_hit),
    .search_data (sq.search_data)
  );

  //----------------------------------------------------------------------
  // Unused signals
  //----------------------------------------------------------------------

  logic [31:0] unused_squash_target;
  assign unused_squash_target = squash.target;

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------
  // One character per entry: '.' empty, 'a' allocated, 'F' filled

`ifndef SYNTHESIS
  function string trace(
    // verilator lint_off UNUSEDSIGNAL
    int trace_level
    // verilator lint_on UNUSEDSIGNAL
  );
    trace = "[";
    for( int i = 0; i < p_depth; i = i + 1 ) begin
      if( !val[i] )
        trace = {trace, "."};
      else if( !filled[i] )
        trace = {trace, "a"};
      else
        trace = {trace, "F"};
    end
    trace = {trace, "]"};
  endfunction
`endif

endmodule

`endif // HW_WRITEBACK_STORE_QUEUE_V
