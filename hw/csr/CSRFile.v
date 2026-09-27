//========================================================================
// CSRFile.v
//========================================================================
// Author: Emily Lan
//========================================================================
// Stores all control and status registers (CSRs)
//  - Reads are combinational through CSRIntf
//  - Writes are sequential through CSRNotif

`ifndef HW_CSR_CSRFILE_V
`define HW_CSR_CSRFILE_V

`include "defs/CSRDefs.v"
`include "defs/UArch.v"
`include "intf/CSRIntf.v"
`include "intf/CSRNotif.v"
`include "intf/SquashNotif.v"

import CSRDefs::*;
import UArch::*;

module CSRFile (
  input  logic    clk,
  input  logic    rst,

  CSRIntf.F_intf  csr,
  CSRNotif.sub    csr_notif,
  SquashNotif.pub squash
);

  //----------------------------------------------------------------------
  // State
  //----------------------------------------------------------------------

  logic  [4:0] fflags;
  logic  [2:0] frm;
  logic        mie;
  logic        mpie;
  logic [31:2] mtvec_base;
  logic [31:0] mscratch;
  logic [31:2] mepc;
  logic        mcause_int;
  logic  [4:0] mcause_code;
  logic [31:0] mtval;

  //----------------------------------------------------------------------
  // Read
  //----------------------------------------------------------------------

  function automatic logic [31:0] read_csr( input logic [11:0] addr );
    case( addr )
      CSR_FFLAGS:   return { 27'b0, fflags };
      CSR_FRM:      return { 29'b0, frm };
      CSR_FCSR:     return { 24'b0, frm, fflags };
      CSR_MSTATUS:  return { 19'b0, 2'b11, 3'b0, mpie, 3'b0, mie, 3'b0 };
      CSR_MTVEC:    return { mtvec_base, 2'b00 };
      CSR_MSCRATCH: return mscratch;
      CSR_MEPC:     return { mepc, 2'b00 };
      CSR_MCAUSE:   return { mcause_int, 26'b0, mcause_code };
      CSR_MTVAL:    return mtval;
      default:      return 32'b0;
    endcase
  endfunction

  logic [31:0] old_val;

  always_comb begin
    csr.rdata = read_csr( csr.addr );
    old_val   = read_csr( csr_notif.addr );
  end

  //----------------------------------------------------------------------
  // CSR operations
  //----------------------------------------------------------------------

  logic [31:0] new_val;
  logic        csr_op;

  always_comb begin
    case( csr_notif.cmd )
      CSR_CMD_WRITE: new_val = csr_notif.wdata;
      CSR_CMD_SET:   new_val = old_val |  csr_notif.wdata;
      CSR_CMD_CLEAR: new_val = old_val & ~csr_notif.wdata;
      default:       new_val = old_val;
    endcase
  end

  assign csr_op = ( csr_notif.cmd == CSR_CMD_WRITE ) |
                  ( csr_notif.cmd == CSR_CMD_SET   ) |
                  ( csr_notif.cmd == CSR_CMD_CLEAR );

  //----------------------------------------------------------------------
  // Update
  //----------------------------------------------------------------------
  // Priority: exception > MRET > CSR operation

  always_ff @( posedge clk ) begin
    if( rst ) begin
      fflags      <= '0;
      frm         <= '0;
      mie         <= 1'b0;
      mpie        <= 1'b0;
      mtvec_base  <= '0;
      mscratch    <= '0;
      mepc        <= '0;
      mcause_int  <= 1'b0;
      mcause_code <= '0;
      mtval       <= '0;
    end
    else if( csr_notif.val ) begin
      if( csr_notif.exc_val ) begin // Trap entry
        mepc        <= csr_notif.pc[31:2];
        mcause_int  <= 1'b0;
        mcause_code <= csr_notif.exc_cause;
        mtval       <= '0;
        mpie        <= mie;
        mie         <= 1'b0;
      end
      else if( csr_notif.cmd == CSR_CMD_MRET ) begin // Trap return
        mie         <= mpie;
        mpie        <= 1'b1;
      end
      else if( csr_op ) begin
        case( csr_notif.addr )
          CSR_FFLAGS:   fflags <= new_val[4:0];
          CSR_FRM:      frm    <= new_val[2:0];
          CSR_FCSR: begin
            frm         <= new_val[7:5];
            fflags      <= new_val[4:0];
          end
          CSR_MSTATUS: begin
            mie         <= new_val[3];
            mpie        <= new_val[7];
          end
          CSR_MTVEC:    mtvec_base <= new_val[31:2];
          CSR_MSCRATCH: mscratch   <= new_val;
          CSR_MEPC:     mepc       <= new_val[31:2];
          CSR_MCAUSE: begin
            mcause_int  <= new_val[31];
            mcause_code <= new_val[4:0];
          end
          CSR_MTVAL:    mtval      <= new_val;
          default: ;
        endcase
      end
    end
  end

  //----------------------------------------------------------------------
  // Trap Redirect
  //----------------------------------------------------------------------

  assign squash.val     = csr_notif.val & ( csr_notif.exc_val |
                                            ( csr_notif.cmd == CSR_CMD_MRET ) );
  assign squash.target  = csr_notif.exc_val ? { mtvec_base, 2'b00 }
                                            : { mepc, 2'b00 };
  assign squash.seq_num = csr_notif.seq_num;

  //----------------------------------------------------------------------
  // Unused signals
  //----------------------------------------------------------------------

  logic [1:0] unused_csr_notif_pc;
  assign unused_csr_notif_pc = csr_notif.pc[1:0];

endmodule

`endif // HW_CSR_CSRFILE_V
