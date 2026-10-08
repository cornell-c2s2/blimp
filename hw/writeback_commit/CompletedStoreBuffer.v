//========================================================================
// CompletedStoreBuffer.v
//========================================================================
// Holds committed stores in commit order and retires them to memory.
// Never squashed.
//
//  - Push:   a committing store enters at the tail
//  - Retire: the head's write is sent to memory (at most one write
//            outstanding); the head is dequeued when the write is
//            acknowledged
//  - Search: per byte lane, the youngest entry for a word. Entries stay
//            searchable until their write is acknowledged
//
// See STORE_QUEUE_DESIGN.md.

`ifndef HW_WRITEBACK_COMPLETED_STORE_BUFFER_V
`define HW_WRITEBACK_COMPLETED_STORE_BUFFER_V

`include "hw/writeback_commit/StoreBufferSearch.v"
`include "intf/CompletedStoreBufferIntf.v"
`include "intf/MemIntf.v"
`include "types/MemMsg.v"

module CompletedStoreBuffer #(
  parameter p_depth     = 4,
  parameter p_opaq_bits = 8
)(
  input  logic clk,
  input  logic rst,

  //----------------------------------------------------------------------
  // Search
  //----------------------------------------------------------------------

  CompletedStoreBufferIntf.CSB_intf csb,

  //----------------------------------------------------------------------
  // Retire (memory writes)
  //----------------------------------------------------------------------

  MemIntf.client mem,

  //----------------------------------------------------------------------
  // Push
  //----------------------------------------------------------------------

  input  logic        push_en,
  input  logic [31:2] push_addr,
  input  logic  [3:0] push_strb,
  input  logic [31:0] push_data,
  output logic        push_rdy
);

  localparam p_ptr_bits = ( p_depth > 1 ) ? $clog2( p_depth ) : 1;

  //----------------------------------------------------------------------
  // State
  //----------------------------------------------------------------------

  logic        val  [p_depth];
  logic [31:2] addr [p_depth];
  logic  [3:0] strb [p_depth];
  logic [31:0] data [p_depth];

  logic [p_ptr_bits-1:0] head;
  logic [p_ptr_bits-1:0] tail;
  logic                  sent; // The head's write is outstanding

  logic full, empty;
  assign full  = val[tail];
  assign empty = !val[head];

  function automatic logic [p_ptr_bits-1:0] incr( input logic [p_ptr_bits-1:0] ptr );
    if( int'(ptr) == p_depth - 1 )
      return '0;
    else
      return ptr + 1;
  endfunction

  //----------------------------------------------------------------------
  // Retire
  //----------------------------------------------------------------------
  // When the buffer is empty, a store being pushed is sent in the same
  // cycle (it is written at the head). The next write is only sent the
  // cycle after an ack, as sent is still set in the ack cycle.

  logic pop;
  logic req_xfer;

  assign mem.resp_rdy = 1'b1;
  assign pop          = sent & mem.resp_val;

  assign mem.req_val = !sent & ( !empty | push_en );
  assign req_xfer    = mem.req_val & mem.req_rdy;

  always_comb begin
    mem.req_msg.op     = MEM_MSG_WRITE;
    mem.req_msg.opaque = '0;
    if( empty ) begin
      mem.req_msg.addr = { push_addr, 2'b00 };
      mem.req_msg.strb = push_strb;
      mem.req_msg.data = push_data;
    end else begin
      mem.req_msg.addr = { addr[head], 2'b00 };
      mem.req_msg.strb = strb[head];
      mem.req_msg.data = data[head];
    end
  end

  //----------------------------------------------------------------------
  // Push and pop
  //----------------------------------------------------------------------

  // Bypass: a slot freed by a pop is usable in the same cycle
  assign push_rdy = !full | pop;

  logic push_xfer;
  assign push_xfer = push_en & push_rdy;

  always_ff @( posedge clk ) begin
    if( rst ) begin
      head <= '0;
      tail <= '0;
      sent <= 1'b0;
      for( int i = 0; i < p_depth; i = i + 1 ) begin
        val[i]  <= 1'b0;
        addr[i] <= '0;
        strb[i] <= '0;
        data[i] <= '0;
      end
    end else begin
      // Pop (on ack)
      if( pop ) begin
        val[head] <= 1'b0;
        head      <= incr( head );
      end

      // Push (after pop: when full, the push reuses the slot freed by the
      // pop, and its write wins)
      if( push_xfer ) begin
        val[tail]  <= 1'b1;
        addr[tail] <= push_addr;
        strb[tail] <= push_strb;
        data[tail] <= push_data;
        tail       <= incr( tail );
      end

      // Outstanding write (req_xfer and pop are exclusive: req needs
      // !sent, pop needs sent)
      if( req_xfer )
        sent <= 1'b1;
      else if( pop )
        sent <= 1'b0;
    end
  end

  //----------------------------------------------------------------------
  // Search
  //----------------------------------------------------------------------

  StoreBufferSearch #(
    .p_depth    (p_depth),
    .p_ptr_bits (p_ptr_bits)
  ) search (
    .eligible    (val),
    .addr        (addr),
    .strb        (strb),
    .data        (data),
    .tail        (tail),
    .search_addr (csb.search_addr),
    .hit         (csb.search_hit),
    .search_data (csb.search_data)
  );

  //----------------------------------------------------------------------
  // Unused signals
  //----------------------------------------------------------------------

  t_op                    unused_resp_op;
  logic [p_opaq_bits-1:0] unused_resp_opaque;
  logic            [31:0] unused_resp_addr;
  logic             [3:0] unused_resp_strb;
  logic            [31:0] unused_resp_data;

  assign unused_resp_op     = mem.resp_msg.op;
  assign unused_resp_opaque = mem.resp_msg.opaque;
  assign unused_resp_addr   = mem.resp_msg.addr;
  assign unused_resp_strb   = mem.resp_msg.strb;
  assign unused_resp_data   = mem.resp_msg.data;

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------
  // One character per entry: '.' empty, 'C' committed, 'S' head sent

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
      else if( sent & ( p_ptr_bits'(i) == head ) )
        trace = {trace, "S"};
      else
        trace = {trace, "C"};
    end
    trace = {trace, "]"};
  endfunction
`endif

endmodule

`endif // HW_WRITEBACK_COMPLETED_STORE_BUFFER_V
