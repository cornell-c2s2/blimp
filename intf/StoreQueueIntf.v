//========================================================================
// StoreQueueIntf.v
//========================================================================
// The interface to the store queue: allocation (decode), and filling
// and searching (load-store unit)

`ifndef INTF_STORE_QUEUE_INTF_V
`define INTF_STORE_QUEUE_INTF_V

//------------------------------------------------------------------------
// StoreQueueIntf
//------------------------------------------------------------------------

interface StoreQueueIntf
#(
  parameter p_seq_num_bits = 5,
  parameter p_sq_idx_bits  = 2
);

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Signals
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  // Allocate (decode)
  logic                      alloc_val;
  logic [p_seq_num_bits-1:0] alloc_seq_num;
  logic                      alloc_rdy;
  logic  [p_sq_idx_bits-1:0] alloc_idx;

  // Fill (load-store unit)
  logic                      fill_val;
  logic  [p_sq_idx_bits-1:0] fill_idx;
  logic               [31:2] fill_addr;  // Word address
  logic                [3:0] fill_strb;  // Byte lanes written
  logic               [31:0] fill_data;  // Lane-aligned data

  // Search (load-store unit)
  logic               [31:2] search_addr;
  logic                [3:0] search_hit;  // Per lane: some filled entry writes it
  logic               [31:0] search_data; // Per lane: byte from the youngest such entry

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Module-facing Ports
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  modport D_intf (
    output alloc_val,
    output alloc_seq_num,
    input  alloc_rdy,
    input  alloc_idx
  );

  modport X_intf (
    output fill_val,
    output fill_idx,
    output fill_addr,
    output fill_strb,
    output fill_data,

    output search_addr,
    input  search_hit,
    input  search_data
  );

  modport SQ_intf (
    input  alloc_val,
    input  alloc_seq_num,
    output alloc_rdy,
    output alloc_idx,

    input  fill_val,
    input  fill_idx,
    input  fill_addr,
    input  fill_strb,
    input  fill_data,

    input  search_addr,
    output search_hit,
    output search_data
  );

endinterface

`endif // INTF_STORE_QUEUE_INTF_V
