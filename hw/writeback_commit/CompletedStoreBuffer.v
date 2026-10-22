//========================================================================
// CompletedStoreBuffer.v
//========================================================================
// Holds committed stores
//
//  - Push:   in commit, a committed store is pushed
//  - Retire: to memory, the head store is written
//            and popped when the write is acknowledged
//  - Search: in LSU, a load searches for stores

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

  CompletedStoreBufferIntf.CSB_intf csb_intf,

  //----------------------------------------------------------------------
  // Retire (memory writes)
  //----------------------------------------------------------------------

  MemIntf.client mem,

  //----------------------------------------------------------------------
  // Push
  //----------------------------------------------------------------------

  input  logic        push_val,
  input  logic [31:2] push_addr,
  input  logic  [3:0] push_strb,
  input  logic [31:0] push_data,
  output logic        push_rdy
);

  localparam p_ptr_bits = ( p_depth > 1 ) ? $clog2( p_depth ) : 1;

  //----------------------------------------------------------------------
  // State
  //----------------------------------------------------------------------

  typedef struct packed {
    logic        val;
    logic [31:2] addr;
    logic  [3:0] strb;
    logic [31:0] data;
  } t_csb_entry;

  t_csb_entry csb [p_depth];

  logic [p_ptr_bits-1:0] head;
  logic [p_ptr_bits-1:0] tail;
  logic                  sent; // head is waiting for ack

  logic full, empty;
  assign full  = csb[tail].val;
  assign empty = !csb[head].val;

  //----------------------------------------------------------------------
  // Retire
  //----------------------------------------------------------------------
  // when empty, a pushed store is sent in the same cycle

  logic pop;
  logic req_xfer;

  assign mem.resp_rdy = 1'b1;
  assign pop          = sent & mem.resp_val;

  assign mem.req_val = !sent & ( !empty | push_val );
  assign req_xfer    = mem.req_val & mem.req_rdy;

  always_comb begin
    mem.req_msg.op     = MEM_MSG_WRITE;
    mem.req_msg.opaque = '0;
    if( empty ) begin
      mem.req_msg.addr = { push_addr, 2'b00 };
      mem.req_msg.strb = push_strb;
      mem.req_msg.data = push_data;
    end else begin
      mem.req_msg.addr = { csb[head].addr, 2'b00 };
      mem.req_msg.strb = csb[head].strb;
      mem.req_msg.data = csb[head].data;
    end
  end

  //----------------------------------------------------------------------
  // Push and pop
  //----------------------------------------------------------------------

  // slot freed by pop is available immediately
  assign push_rdy = !full | pop;

  logic push_xfer;
  assign push_xfer = push_val & push_rdy;

  always_ff @( posedge clk ) begin
    if( rst ) begin
      head <= '0;
      tail <= '0;
      sent <= 1'b0;
      for( int i = 0; i < p_depth; i = i + 1 )
        csb[i] <= '0;
    end else begin
      // pop
      if( pop ) begin
        csb[head].val <= 1'b0;
        head          <= ( int'(head) == p_depth - 1 ) ? 0 : head + 1;
      end

      // push
      if( push_xfer ) begin
        csb[tail].val  <= 1'b1;
        csb[tail].addr <= push_addr;
        csb[tail].strb <= push_strb;
        csb[tail].data <= push_data;
        tail           <= ( int'(tail) == p_depth - 1 ) ? 0 : tail + 1;
      end

      // sent update
      if( req_xfer )
        sent <= 1'b1;
      else if( pop )
        sent <= 1'b0;
    end
  end

  //----------------------------------------------------------------------
  // Search
  //----------------------------------------------------------------------

  logic        search_val [p_depth];
  logic [31:2] entry_addr [p_depth];
  logic  [3:0] entry_strb [p_depth];
  logic [31:0] entry_data [p_depth];

  always_comb begin
    for( int i = 0; i < p_depth; i = i + 1 ) begin
      search_val[i] = csb[i].val;
      entry_addr[i] = csb[i].addr;
      entry_strb[i] = csb[i].strb;
      entry_data[i] = csb[i].data;
    end
  end

  StoreBufferSearch #(
    .p_depth    (p_depth),
    .p_ptr_bits (p_ptr_bits)
  ) search (
    .search_val  (search_val),
    .addr        (entry_addr),
    .strb        (entry_strb),
    .data        (entry_data),
    .tail        (tail),
    .search_addr (csb_intf.search_addr),
    .hit         (csb_intf.search_hit),
    .search_data (csb_intf.search_data)
  );

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
      if( !csb[i].val )
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
