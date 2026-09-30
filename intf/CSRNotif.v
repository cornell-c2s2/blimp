//========================================================================
// CSRNotif.v
//========================================================================
// The notification interface for applying an instruction's commit-time
// action to the CSR file: a CSR operation (cmd), or an exception (exc_val)

`ifndef INTF_CSR_NOTIF_V
`define INTF_CSR_NOTIF_V

//------------------------------------------------------------------------
// CSRNotif
//------------------------------------------------------------------------

interface CSRNotif
#(
  parameter p_seq_num_bits = 5
);

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Signals
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  logic                      val;
  logic                [2:0] cmd;
  logic               [11:0] addr;
  logic               [31:0] wdata;
  logic                      exc_val;
  logic                [4:0] exc_cause;
  logic               [31:0] pc;
  logic [p_seq_num_bits-1:0] seq_num;

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Module-facing Ports
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  // Publish
  modport pub (
    output val,
    output cmd,
    output addr,
    output wdata,
    output exc_val,
    output exc_cause,
    output pc,
    output seq_num
  );

  // Subscribe
  modport sub (
    input val,
    input cmd,
    input addr,
    input wdata,
    input exc_val,
    input exc_cause,
    input pc,
    input seq_num
  );

endinterface

`endif // INTF_CSR_NOTIF_V
