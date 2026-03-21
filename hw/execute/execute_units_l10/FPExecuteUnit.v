//========================================================================
// FPExecuteUnit.v
//========================================================================
// Wrapper for BLIMP floating-point execute subunits
//
// Takes one FP pipe input and internally routes to:
// - ALUF              (FADD/FSUB)
// - FPUMult           (FMUL)
// - FPInstUnitL10     (FSGNJ/FCVT/FMV)
// - FPULoadStoreUnitL10 (FLW/FSW)
//
// Produces one shared X/W output and one private memory interface.
//
// Author: Sumaia Jewena
//========================================================================

`ifndef HW_EXECUTE_EXECUTE_UNITS_L10_FPEXECUTEUNIT_V
`define HW_EXECUTE_EXECUTE_UNITS_L10_FPEXECUTEUNIT_V

`include "defs/UArch.v"
`include "intf/D__XIntf.v"
`include "intf/X__WIntf.v"
`include "intf/MemIntf.v"
`include "hw/execute/ExQueue.v"
`include "hw/execute/execute_units_l8/ALUF.v"
`include "hw/execute/execute_units_l9/FPUMult.v"
`include "hw/execute/execute_units_l10/FPInstUnitL10.v"
`include "hw/execute/execute_units_l10/FPULoadStoreUnitL10.v"

import UArch::*;

module FPExecuteUnit #(
  parameter p_opaq_bits = 8
)(
  input  logic clk,
  input  logic rst,

  D__XIntf.X_intf D,
  X__WIntf.X_intf W,
  MemIntf.client  mem
);

  localparam p_seq_num_bits   = D.p_seq_num_bits;
  localparam p_phys_addr_bits = D.p_phys_addr_bits;

  //----------------------------------------------------------------------
  // Internal interfaces
  //----------------------------------------------------------------------

  D__XIntf #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (p_phys_addr_bits)
  ) fp_addsub_d_intf();

  D__XIntf #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (p_phys_addr_bits)
  ) fp_mul_d_intf();

  D__XIntf #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (p_phys_addr_bits)
  ) fp_inst_d_intf();

  D__XIntf #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (p_phys_addr_bits)
  ) fp_mem_d_intf();

  X__WIntf #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (p_phys_addr_bits)
  ) buffer_fp_addsub_intf();

  X__WIntf #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (p_phys_addr_bits)
  ) buffer_fp_mul_intf();

  X__WIntf #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (p_phys_addr_bits)
  ) buffer_fp_inst_intf();

  X__WIntf #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (p_phys_addr_bits)
  ) buffer_fp_mem_intf();

  X__WIntf #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (p_phys_addr_bits)
  ) buffer_fp_intf();

  //----------------------------------------------------------------------
  // Internal select logic
  //----------------------------------------------------------------------

  logic fp_sel_addsub, fp_sel_mul, fp_sel_inst, fp_sel_mem;

  always_comb begin
    fp_sel_addsub = 1'b0;
    fp_sel_mul    = 1'b0;
    fp_sel_inst   = 1'b0;
    fp_sel_mem    = 1'b0;

    unique case ( D.uop )
      OP_FADD_S,
      OP_FSUB_S: begin
        fp_sel_addsub = 1'b1;
      end

      OP_FMUL_S: begin
        fp_sel_mul = 1'b1;
      end

      OP_FSGNJ_S,
      OP_FCVT_W_S,
      OP_FMV_X_W,
      OP_FMV_W_X: begin
        fp_sel_inst = 1'b1;
      end

      OP_FLW,
      OP_FSW: begin
        fp_sel_mem = 1'b1;
      end

      default: begin
        fp_sel_addsub = 1'b0;
        fp_sel_mul    = 1'b0;
        fp_sel_inst   = 1'b0;
        fp_sel_mem    = 1'b0;
      end
    endcase
  end

  //----------------------------------------------------------------------
  // Route common fields to all internal FP D interfaces
  //----------------------------------------------------------------------

  assign fp_addsub_d_intf.pc      = D.pc;
  assign fp_addsub_d_intf.op1     = D.op1;
  assign fp_addsub_d_intf.op2     = D.op2;
  assign fp_addsub_d_intf.waddr   = D.waddr;
  assign fp_addsub_d_intf.uop     = D.uop;
  assign fp_addsub_d_intf.seq_num = D.seq_num;
  assign fp_addsub_d_intf.preg    = D.preg;
  assign fp_addsub_d_intf.ppreg   = D.ppreg;
  assign fp_addsub_d_intf.is_fp   = D.is_fp;
  assign fp_addsub_d_intf.op3     = D.op3;
  assign fp_addsub_d_intf.val     = D.val & fp_sel_addsub;

  assign fp_mul_d_intf.pc      = D.pc;
  assign fp_mul_d_intf.op1     = D.op1;
  assign fp_mul_d_intf.op2     = D.op2;
  assign fp_mul_d_intf.waddr   = D.waddr;
  assign fp_mul_d_intf.uop     = D.uop;
  assign fp_mul_d_intf.seq_num = D.seq_num;
  assign fp_mul_d_intf.preg    = D.preg;
  assign fp_mul_d_intf.ppreg   = D.ppreg;
  assign fp_mul_d_intf.is_fp   = D.is_fp;
  assign fp_mul_d_intf.op3     = D.op3;
  assign fp_mul_d_intf.val     = D.val & fp_sel_mul;

  assign fp_inst_d_intf.pc      = D.pc;
  assign fp_inst_d_intf.op1     = D.op1;
  assign fp_inst_d_intf.op2     = D.op2;
  assign fp_inst_d_intf.waddr   = D.waddr;
  assign fp_inst_d_intf.uop     = D.uop;
  assign fp_inst_d_intf.seq_num = D.seq_num;
  assign fp_inst_d_intf.preg    = D.preg;
  assign fp_inst_d_intf.ppreg   = D.ppreg;
  assign fp_inst_d_intf.is_fp   = D.is_fp;
  assign fp_inst_d_intf.op3     = D.op3;
  assign fp_inst_d_intf.val     = D.val & fp_sel_inst;

  assign fp_mem_d_intf.pc      = D.pc;
  assign fp_mem_d_intf.op1     = D.op1;
  assign fp_mem_d_intf.op2     = D.op2;
  assign fp_mem_d_intf.waddr   = D.waddr;
  assign fp_mem_d_intf.uop     = D.uop;
  assign fp_mem_d_intf.seq_num = D.seq_num;
  assign fp_mem_d_intf.preg    = D.preg;
  assign fp_mem_d_intf.ppreg   = D.ppreg;
  assign fp_mem_d_intf.is_fp   = D.is_fp;
  assign fp_mem_d_intf.op3     = D.op3;
  assign fp_mem_d_intf.val     = D.val & fp_sel_mem;

  //----------------------------------------------------------------------
  // Ready routing
  //----------------------------------------------------------------------

  always_comb begin
    D.rdy = 1'b1;

    if ( D.val ) begin
      if ( fp_sel_addsub )
        D.rdy = fp_addsub_d_intf.rdy;
      else if ( fp_sel_mul )
        D.rdy = fp_mul_d_intf.rdy;
      else if ( fp_sel_inst )
        D.rdy = fp_inst_d_intf.rdy;
      else if ( fp_sel_mem )
        D.rdy = fp_mem_d_intf.rdy;
      else
        D.rdy = 1'b0;
    end
  end

  //----------------------------------------------------------------------
  // Subunits
  //----------------------------------------------------------------------

  ALUF FP_ADD_SUB_XU (
    .D (fp_addsub_d_intf),
    .W (buffer_fp_addsub_intf),
    .*
  );

  FPUMult FP_MUL_XU (
    .D (fp_mul_d_intf),
    .W (buffer_fp_mul_intf),
    .*
  );

  FPInstUnitL10 FP_INST_XU (
    .D (fp_inst_d_intf),
    .W (buffer_fp_inst_intf),
    .*
  );

  FPULoadStoreUnitL10 #(
    .p_opaq_bits (p_opaq_bits)
  ) FP_MEM_XU (
    .D   (fp_mem_d_intf),
    .W   (buffer_fp_mem_intf),
    .mem (mem),
    .*
  );

  //----------------------------------------------------------------------
  // Shared FP output arbitration/mux
  //----------------------------------------------------------------------

  assign buffer_fp_addsub_intf.rdy = buffer_fp_intf.rdy &
                                     buffer_fp_addsub_intf.val;

  assign buffer_fp_mul_intf.rdy    = buffer_fp_intf.rdy &
                                     (~buffer_fp_addsub_intf.val) &
                                     buffer_fp_mul_intf.val;

  assign buffer_fp_inst_intf.rdy   = buffer_fp_intf.rdy &
                                     (~buffer_fp_addsub_intf.val) &
                                     (~buffer_fp_mul_intf.val) &
                                     buffer_fp_inst_intf.val;

  assign buffer_fp_mem_intf.rdy    = buffer_fp_intf.rdy &
                                     (~buffer_fp_addsub_intf.val) &
                                     (~buffer_fp_mul_intf.val) &
                                     (~buffer_fp_inst_intf.val) &
                                     buffer_fp_mem_intf.val;

  always_comb begin
    buffer_fp_intf.val     = 1'b0;
    buffer_fp_intf.pc      = '0;
    buffer_fp_intf.waddr   = '0;
    buffer_fp_intf.wdata   = '0;
    buffer_fp_intf.wen     = 1'b0;
    buffer_fp_intf.seq_num = '0;
    buffer_fp_intf.preg    = '0;
    buffer_fp_intf.ppreg   = '0;
    buffer_fp_intf.is_fp   = 1'b0;

    if ( buffer_fp_addsub_intf.val ) begin
      buffer_fp_intf.val     = buffer_fp_addsub_intf.val;
      buffer_fp_intf.pc      = buffer_fp_addsub_intf.pc;
      buffer_fp_intf.waddr   = buffer_fp_addsub_intf.waddr;
      buffer_fp_intf.wdata   = buffer_fp_addsub_intf.wdata;
      buffer_fp_intf.wen     = buffer_fp_addsub_intf.wen;
      buffer_fp_intf.seq_num = buffer_fp_addsub_intf.seq_num;
      buffer_fp_intf.preg    = buffer_fp_addsub_intf.preg;
      buffer_fp_intf.ppreg   = buffer_fp_addsub_intf.ppreg;
      buffer_fp_intf.is_fp   = buffer_fp_addsub_intf.is_fp;
    end
    else if ( buffer_fp_mul_intf.val ) begin
      buffer_fp_intf.val     = buffer_fp_mul_intf.val;
      buffer_fp_intf.pc      = buffer_fp_mul_intf.pc;
      buffer_fp_intf.waddr   = buffer_fp_mul_intf.waddr;
      buffer_fp_intf.wdata   = buffer_fp_mul_intf.wdata;
      buffer_fp_intf.wen     = buffer_fp_mul_intf.wen;
      buffer_fp_intf.seq_num = buffer_fp_mul_intf.seq_num;
      buffer_fp_intf.preg    = buffer_fp_mul_intf.preg;
      buffer_fp_intf.ppreg   = buffer_fp_mul_intf.ppreg;
      buffer_fp_intf.is_fp   = buffer_fp_mul_intf.is_fp;
    end
    else if ( buffer_fp_inst_intf.val ) begin
      buffer_fp_intf.val     = buffer_fp_inst_intf.val;
      buffer_fp_intf.pc      = buffer_fp_inst_intf.pc;
      buffer_fp_intf.waddr   = buffer_fp_inst_intf.waddr;
      buffer_fp_intf.wdata   = buffer_fp_inst_intf.wdata;
      buffer_fp_intf.wen     = buffer_fp_inst_intf.wen;
      buffer_fp_intf.seq_num = buffer_fp_inst_intf.seq_num;
      buffer_fp_intf.preg    = buffer_fp_inst_intf.preg;
      buffer_fp_intf.ppreg   = buffer_fp_inst_intf.ppreg;
      buffer_fp_intf.is_fp   = buffer_fp_inst_intf.is_fp;
    end
    else if ( buffer_fp_mem_intf.val ) begin
      buffer_fp_intf.val     = buffer_fp_mem_intf.val;
      buffer_fp_intf.pc      = buffer_fp_mem_intf.pc;
      buffer_fp_intf.waddr   = buffer_fp_mem_intf.waddr;
      buffer_fp_intf.wdata   = buffer_fp_mem_intf.wdata;
      buffer_fp_intf.wen     = buffer_fp_mem_intf.wen;
      buffer_fp_intf.seq_num = buffer_fp_mem_intf.seq_num;
      buffer_fp_intf.preg    = buffer_fp_mem_intf.preg;
      buffer_fp_intf.ppreg   = buffer_fp_mem_intf.ppreg;
      buffer_fp_intf.is_fp   = buffer_fp_mem_intf.is_fp;
    end
  end

  ExQueue #(1) fp_buf (
    .in  (buffer_fp_intf),
    .out (W),
    .*
  );

  //----------------------------------------------------------------------
  // Linetrace
  //----------------------------------------------------------------------

`ifndef SYNTHESIS
  function string trace( int trace_level );
    trace = "";
    trace = {trace, FP_ADD_SUB_XU.trace( trace_level )};
    trace = {trace, "/"};
    trace = {trace, FP_MUL_XU.trace( trace_level )};
    trace = {trace, "/"};
    trace = {trace, FP_INST_XU.trace( trace_level )};
    trace = {trace, "/"};
    trace = {trace, FP_MEM_XU.trace( trace_level )};
  endfunction
`endif

endmodule

`endif // HW_EXECUTE_EXECUTE_UNITS_L10_FPEXECUTEUNIT_V
