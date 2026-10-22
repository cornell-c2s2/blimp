//========================================================================
// StoreQueue.v
//========================================================================
// Holds speculative stores
//
//  - Allocate: in decode, a store allocates an entry
//  - Fill:     in LSU, a store fills entry with store data
//  - Search:   in LSU, a load searches for stores
//  - Dequeue:  in commit, a store is dequeued
//  - Squash:   entries younger than the squashing instruction are removed
//              (uses commit notif to determine relative age)

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

  StoreQueueIntf.SQ_intf sq_intf,

  //----------------------------------------------------------------------
  // Squash
  //----------------------------------------------------------------------

  SquashNotif.sub squash,

  //----------------------------------------------------------------------
  // Commit
  //----------------------------------------------------------------------

  CommitNotif.sub commit,

  //----------------------------------------------------------------------
  // Dequeue
  //----------------------------------------------------------------------

  input  logic                      deq_rdy,
  output logic                      deq_val,
  output logic [p_seq_num_bits-1:0] deq_seq_num,
  output logic               [31:2] deq_addr,
  output logic                [3:0] deq_strb,
  output logic               [31:0] deq_data
);

  //----------------------------------------------------------------------
  // State
  //----------------------------------------------------------------------

  typedef struct packed {
    logic                      val;
    logic                      filled;
    logic [p_seq_num_bits-1:0] seq_num;
    logic               [31:2] addr;
    logic                [3:0] strb;
    logic               [31:0] data;
  } t_sq_entry;

  t_sq_entry sq [p_depth];

  logic [p_idx_bits-1:0] head;
  logic [p_idx_bits-1:0] tail;

  logic full;
  assign full = sq[tail].val;

  //----------------------------------------------------------------------
  // Squash
  //----------------------------------------------------------------------

  SeqAge seq_age (
    .*
  );

  logic                  removed [p_depth];
  logic [p_idx_bits-1:0] squash_tail;

  always_comb begin
    for( int i = 0; i < p_depth; i = i + 1 )
      removed[i] = squash.val & sq[i].val &
                   seq_age.is_older( squash.seq_num, sq[i].seq_num );
  end

  always_comb begin
    int idx;
    squash_tail = head;
    for( int k = 0; k < p_depth; k = k + 1 ) begin
      idx = int'(head) + k;
      if( idx >= p_depth )
        idx = idx - p_depth;
      if( sq[idx].val & !removed[idx] )
        squash_tail = ( idx == p_depth - 1 ) ? 0 : p_idx_bits'(idx + 1);
    end
  end

  //----------------------------------------------------------------------
  // Allocate, fill and dequeue
  //----------------------------------------------------------------------

  logic deq_xfer;
  logic alloc_xfer;
  logic fill_xfer;

  assign deq_val   = sq[head].val & sq[head].filled;
  assign deq_xfer  = deq_rdy & deq_val;

  // slot freed by dequeue is available immediately
  assign sq_intf.alloc_rdy = !full | deq_xfer;
  assign sq_intf.alloc_idx = tail;

  // squash prevents allocation of new entries and fills of removed entries
  assign alloc_xfer = sq_intf.alloc_val & sq_intf.alloc_rdy & !squash.val;
  assign fill_xfer  = sq_intf.fill_val & sq[sq_intf.fill_idx].val & !removed[sq_intf.fill_idx];

  always_ff @( posedge clk ) begin
    if( rst ) begin
      head <= '0;
      tail <= '0;
      for( int i = 0; i < p_depth; i = i + 1 )
        sq[i] <= '0;
    end else begin
      // squash
      for( int i = 0; i < p_depth; i = i + 1 ) begin
        if( removed[i] ) sq[i].val <= 1'b0;
      end

      // fill
      if( fill_xfer ) begin
        sq[sq_intf.fill_idx].filled <= 1'b1;
        sq[sq_intf.fill_idx].addr   <= sq_intf.fill_addr;
        sq[sq_intf.fill_idx].strb   <= sq_intf.fill_strb;
        sq[sq_intf.fill_idx].data   <= sq_intf.fill_data;
      end

      // dequeue
      if( deq_xfer ) begin
        sq[head].val <= 1'b0;
        head         <= ( int'(head) == p_depth - 1 ) ? 0 : head + 1;
      end

      // allocate
      if( alloc_xfer ) begin
        sq[tail].val     <= 1'b1;
        sq[tail].filled  <= 1'b0;
        sq[tail].seq_num <= sq_intf.alloc_seq_num;
      end

      // tail update
      if( squash.val )
        tail <= squash_tail;
      else if( alloc_xfer )
        tail <= ( int'(tail) == p_depth - 1 ) ? 0 : tail + 1;
    end
  end

  //----------------------------------------------------------------------
  // Dequeue outputs
  //----------------------------------------------------------------------

  assign deq_seq_num = sq[head].seq_num;
  assign deq_addr    = sq[head].addr;
  assign deq_strb    = sq[head].strb;
  assign deq_data    = sq[head].data;

  //----------------------------------------------------------------------
  // Search
  //----------------------------------------------------------------------

  logic        search_val [p_depth];
  logic [31:2] entry_addr [p_depth];
  logic  [3:0] entry_strb [p_depth];
  logic [31:0] entry_data [p_depth];

  always_comb begin
    for( int i = 0; i < p_depth; i = i + 1 ) begin
      search_val[i] = sq[i].val & sq[i].filled;
      entry_addr[i] = sq[i].addr;
      entry_strb[i] = sq[i].strb;
      entry_data[i] = sq[i].data;
    end
  end

  StoreBufferSearch #(
    .p_depth    (p_depth),
    .p_ptr_bits (p_idx_bits)
  ) search (
    .search_val  (search_val),
    .addr        (entry_addr),
    .strb        (entry_strb),
    .data        (entry_data),
    .tail        (tail),
    .search_addr (sq_intf.search_addr),
    .hit         (sq_intf.search_hit),
    .search_data (sq_intf.search_data)
  );

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
      if( !sq[i].val )
        trace = {trace, "."};
      else if( !sq[i].filled )
        trace = {trace, "a"};
      else
        trace = {trace, "F"};
    end
    trace = {trace, "]"};
  endfunction
`endif

endmodule

`endif // HW_WRITEBACK_STORE_QUEUE_V
