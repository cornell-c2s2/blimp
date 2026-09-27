//========================================================================
// CSRDefs.v
//========================================================================
// Common definitions for control and status registers, as defined by the
// RISC-V privileged architecture

`ifndef DEFS_CSRDEFS_V
`define DEFS_CSRDEFS_V

package CSRDefs;

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // CSR addresses
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  // verilator lint_off UNUSEDPARAM
  parameter logic [11:0] CSR_FFLAGS   = 12'h001;
  parameter logic [11:0] CSR_FRM      = 12'h002;
  parameter logic [11:0] CSR_FCSR     = 12'h003;
  parameter logic [11:0] CSR_MSTATUS  = 12'h300;
  parameter logic [11:0] CSR_MTVEC    = 12'h305;
  parameter logic [11:0] CSR_MSCRATCH = 12'h340;
  parameter logic [11:0] CSR_MEPC     = 12'h341;
  parameter logic [11:0] CSR_MCAUSE   = 12'h342;
  parameter logic [11:0] CSR_MTVAL    = 12'h343;
  // verilator lint_on UNUSEDPARAM

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Exception causes
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // mcause exception codes (interrupt bit clear)

  // verilator lint_off UNUSEDPARAM
  parameter logic [4:0] EXC_BREAKPOINT = 5'd3;
  parameter logic [4:0] EXC_ECALL_M    = 5'd11;
  // verilator lint_on UNUSEDPARAM

  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // CSR commands
  // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  // Operations applied to the CSR file when an instruction commits

  // verilator lint_off UNUSEDPARAM
  parameter logic [2:0] CSR_CMD_NONE  = 3'd0;
  parameter logic [2:0] CSR_CMD_WRITE = 3'd1;
  parameter logic [2:0] CSR_CMD_SET   = 3'd2;
  parameter logic [2:0] CSR_CMD_CLEAR = 3'd3;
  parameter logic [2:0] CSR_CMD_MRET  = 3'd4; // 5-7 reserved
  // verilator lint_on UNUSEDPARAM

endpackage

`endif // DEFS_CSRDEFS_V
