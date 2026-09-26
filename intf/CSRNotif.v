//========================================================================
// CSRNotif.v
//========================================================================
// The notification interface for applying a CSR operation at commit

`ifndef INTF_CSR_NOTIF_V
`define INTF_CSR_NOTIF_V

//------------------------------------------------------------------------
// CSRNotif
//------------------------------------------------------------------------

interface CSRNotif;

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Signals
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  logic        val;
  logic  [2:0] cmd;    // 001 = write, 010 = set, 011 = clear
  logic [11:0] addr;
  logic [31:0] wdata;

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Module-facing Ports
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  // Publish
  modport pub (
    output val,
    output cmd,
    output addr,
    output wdata
  );

  // Subscribe
  modport sub (
    input val,
    input cmd,
    input addr,
    input wdata
  );

endinterface

`endif // INTF_CSR_NOTIF_V
