//========================================================================
// CompletedStoreBufferIntf.v
//========================================================================
// The interface to the completed store buffer: searching (load-store
// unit)

`ifndef INTF_COMPLETED_STORE_BUFFER_INTF_V
`define INTF_COMPLETED_STORE_BUFFER_INTF_V

//------------------------------------------------------------------------
// CompletedStoreBufferIntf
//------------------------------------------------------------------------

interface CompletedStoreBufferIntf;

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Signals
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  logic [31:2] search_addr;
  logic  [3:0] search_hit;  // Per lane: some entry writes it
  logic [31:0] search_data; // Per lane: byte from the youngest such entry

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Module-facing Ports
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  modport X_intf (
    output search_addr,
    input  search_hit,
    input  search_data
  );

  modport CSB_intf (
    input  search_addr,
    output search_hit,
    output search_data
  );

endinterface

`endif // INTF_COMPLETED_STORE_BUFFER_INTF_V
