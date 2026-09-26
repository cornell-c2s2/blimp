//========================================================================
// CSRIntf.v
//========================================================================
// Author: Emily Lan
//========================================================================
// Read-only interface between the CSR execute unit and the CSR register
// file. Writes are applied at commit through CSRNotif.
`ifndef CSR_INTF_V
`define CSR_INTF_V


interface CSRIntf;
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Signals
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  logic [11:0] addr;     // CSR address (e.g. 0x300 mstatus, 0x003 fcsr)
  logic [31:0] rdata;    // Current architectural value (combinational)

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Module-facing Ports
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  // CSR Execute Unit <-> CSR File
  modport X_intf ( // Execute stage side (CSRUnit)
    output addr,
    input  rdata
  );
  modport F_intf ( // CSRFile side
    input  addr,
    output rdata
  );
endinterface
`endif // INTF_CSR_INTF_V
