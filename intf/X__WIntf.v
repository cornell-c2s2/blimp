//========================================================================
// X__WIntf.v
//========================================================================
// The interface definition going between X and W

`ifndef INTF_X__W_INTF_V
`define INTF_X__W_INTF_V

//------------------------------------------------------------------------
// X__WIntf
//------------------------------------------------------------------------

interface X__WIntf
#(
  parameter p_seq_num_bits   = 5,
  parameter p_phys_addr_bits = 6
);

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Signals
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  logic [31:0] pc;
  logic  [4:0] waddr;
  logic [31:0] wdata;
  logic        wen;
  logic        val;
  logic        rdy;

  // verilator lint_off UNUSEDSIGNAL

  // Added in v2
  logic [p_seq_num_bits-1:0] seq_num;

  // Added in v3
  logic [p_phys_addr_bits-1:0] preg;
  logic [p_phys_addr_bits-1:0] ppreg;

  // verilator lint_on UNUSEDSIGNAL

  // verilator lint_off UNUSEDSIGNAL
  // verilator lint_off UNDRIVEN

  // Added in v5
  logic  [2:0] csr_cmd;
  logic [11:0] csr_addr;
  logic [31:0] csr_wdata;
  logic        exc_val;
  logic  [4:0] exc_cause;
  logic [31:0] exc_tval;

  // Resolved redirect, carried with the instruction until retirement.
  logic        redirect;
  logic [31:0] redirect_target;

  // verilator lint_on UNUSEDSIGNAL
  // verilator lint_on UNDRIVEN

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Module-facing Ports
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  modport X_intf (
    output pc,
    output waddr,
    output wdata,
    output wen,
    output val,
    input  rdy,

    // v2
    output seq_num,

    // v3
    output preg,
    output ppreg,

    // v5
    output csr_cmd,
    output csr_addr,
    output csr_wdata,
    output exc_val,
    output exc_cause,
<<<<<<< Updated upstream
    output exc_tval
=======
    output redirect,
    output redirect_target
>>>>>>> Stashed changes
  );

  modport W_intf (
    input  pc,
    input  waddr,
    input  wdata,
    input  wen,
    input  val,
    output rdy,

    // v2
    input  seq_num,

    // v3
    input  preg,
    input  ppreg,

    // v5
    input  csr_cmd,
    input  csr_addr,
    input  csr_wdata,
    input  exc_val,
    input  exc_cause,
<<<<<<< Updated upstream
    input  exc_tval
=======
    input  redirect,
    input  redirect_target
>>>>>>> Stashed changes
  );

endinterface

`endif // INTF_X__W_INTF_V
