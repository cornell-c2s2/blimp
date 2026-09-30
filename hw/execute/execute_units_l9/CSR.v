//========================================================================
// CSR.v
//========================================================================
// Execute unit for CSR and system instructions
//
// Author: Emily Lan
// Last updated: 11/04/25
//========================================================================

`ifndef HW_EXECUTE_EXECUTE_VARIANTS_L9_CSR_V
`define HW_EXECUTE_EXECUTE_VARIANTS_L9_CSR_V

`include "defs/CSRDefs.v"
`include "defs/UArch.v"
`include "intf/D__XIntf.v"
`include "intf/X__WIntf.v"
`include "intf/CSRIntf.v"

import CSRDefs::*;
import UArch::*;

module CSR (
  input  logic clk,
  input  logic rst,

  //----------------------------------------------------------------------
  // D <-> X Interface
  //----------------------------------------------------------------------

  D__XIntf.X_intf D,

  //----------------------------------------------------------------------
  // X <-> W Interface
  //----------------------------------------------------------------------

  X__WIntf.X_intf W,

  //----------------------------------------------------------------------
  // CSR Interface
  //----------------------------------------------------------------------

  CSRIntf.X_intf CSR
);

  localparam p_seq_num_bits   = D.p_seq_num_bits;
  localparam p_phys_addr_bits = D.p_phys_addr_bits;

//----------------------------------------------------------------------
// Register inputs
//----------------------------------------------------------------------

typedef struct packed {
    logic                        val;
    logic                 [31:0] pc;
    logic   [p_seq_num_bits-1:0] seq_num;
    logic                 [31:0] op1;    // Source register value (rs1)
    logic                 [31:0] op2;    // CSR immediate (imm[11:0])
    logic                  [4:0] waddr;  // Destination register address
    rv_uop                       uop;    
    logic [p_phys_addr_bits-1:0] preg;
    logic [p_phys_addr_bits-1:0] ppreg;
} D_input;

  D_input D_reg, D_reg_next;
  logic   D_xfer, W_xfer;

  // verilator lint_off ENUMVALUE

  always_ff @(posedge clk) begin
    if (rst)
      D_reg <= '0;
    else
      D_reg <= D_reg_next;
  end

  always_comb begin
    D_xfer = D.val & D.rdy;
    W_xfer = W.val & W.rdy;

    if (D_xfer)
      D_reg_next = '{
        val:     1'b1,
        pc:      D.pc,
        seq_num: D.seq_num,
        op1:     D.op1,
        op2:     D.op2,
        waddr:   D.waddr,
        uop:     D.uop,
        preg:    D.preg,
        ppreg:   D.ppreg
      };
    else if (W_xfer)
      D_reg_next = '0;
    else
      D_reg_next = D_reg;
  end
  
  // verilator lint_on ENUMVALUE

//----------------------------------------------------------------------
// Operation Decode
//----------------------------------------------------------------------

  logic [2:0] csr_cmd;
  logic       exc_val;
  logic [4:0] exc_cause;

  always_comb begin
    csr_cmd   = CSR_CMD_NONE;
    exc_val   = 1'b0;
    exc_cause = '0;

    unique case (D_reg.uop)
      OP_CSRRW, OP_CSRRWI: csr_cmd = CSR_CMD_WRITE;
      OP_CSRRS, OP_CSRRSI: csr_cmd = CSR_CMD_SET;
      OP_CSRRC, OP_CSRRCI: csr_cmd = CSR_CMD_CLEAR;
      OP_MRET:             csr_cmd = CSR_CMD_MRET;
      OP_ECALL:  begin exc_val = 1'b1; exc_cause = EXC_ECALL_M;    end
      OP_EBREAK: begin exc_val = 1'b1; exc_cause = EXC_BREAKPOINT; end
      default: ;
    endcase
  end

//----------------------------------------------------------------------
// Read the old CSR value
//----------------------------------------------------------------------

  assign CSR.addr = D_reg.op2[11:0]; // CSR address

//----------------------------------------------------------------------
// Action to apply at commit
//----------------------------------------------------------------------

  assign W.csr_cmd   = csr_cmd;
  assign W.csr_addr  = D_reg.op2[11:0];
  assign W.csr_wdata = D_reg.op1; // rs1 value or zimm
  assign W.exc_val   = exc_val;
  assign W.exc_cause = exc_cause;

//----------------------------------------------------------------------
// Assign Remaining Signals
//----------------------------------------------------------------------

  assign W.wdata = CSR.rdata; // Read data from CSR file (previous value in reg)

  assign W.wen   = D_reg.val & (D_reg.waddr != 5'd0) & !exc_val;

  assign W.pc      = D_reg.pc;
  assign W.seq_num = D_reg.seq_num;
  assign W.waddr   = D_reg.waddr;
  assign W.preg    = D_reg.preg;
  assign W.ppreg   = D_reg.ppreg;

//----------------------------------------------------------------------
// Handshake Logic
//----------------------------------------------------------------------

  assign D.rdy = (!D_reg.val) | W.rdy;
  assign W.val = D_reg.val;
//----------------------------------------------------------------------
// Linetracing
//----------------------------------------------------------------------

`ifndef SYNTHESIS
  function string trace (
    // verilator lint_off UNUSEDSIGNAL
    int trace_level
    // verilator lint_on UNUSEDSIGNAL
  );
    if (W.val & W.rdy)
      trace = $sformatf("%h: %8s CSR[%03h]=%h -> %h",
                        W.seq_num,
                        D_reg.uop.name(),
                        CSR.addr,
                        D_reg.op1,
                        CSR.rdata);
    else
      trace = " ";
  endfunction
`endif

endmodule

`endif // HW_EXECUTE_EXECUTE_VARIANTS_L9_CSR_V
