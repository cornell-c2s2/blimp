//========================================================================
// ALULF.v
//========================================================================
// Floating-point adder (IEEE-754 single precision) with dynamic
// normalization and correct round-to-nearest-even logic.

`ifndef HW_EXECUTE_EXECUTE_VARIANTS_L1_ALULF_V
`define HW_EXECUTE_EXECUTE_VARIANTS_L1_ALULF_V

`include "defs/UArch.v"
`include "intf/D__XIntf.v"
`include "intf/X__WIntf.v"

import UArch::*;

module ALULF (
  input  logic clk,
  input  logic rst,

  D__XIntf.X_intf D,
  X__WIntf.X_intf W
);

  localparam p_seq_num_bits   = D.p_seq_num_bits;
  localparam p_phys_addr_bits = D.p_phys_addr_bits;

  // --------------------------------------------------------------------
  // Pipeline register for D inputs
  // --------------------------------------------------------------------
  typedef struct packed {
    logic                        val;
    logic                 [31:0] pc;
    logic   [p_seq_num_bits-1:0] seq_num;
    logic                 [31:0] op1;
    logic                 [31:0] op2;
    logic                  [4:0] waddr;
    rv_uop                       uop;
    logic [p_phys_addr_bits-1:0] preg;
    logic [p_phys_addr_bits-1:0] ppreg;
  } D_input;

  D_input D_reg, D_reg_next;
  logic   D_xfer, W_xfer;

  always_ff @(posedge clk) begin
    if (rst) D_reg <= '0;
    else     D_reg <= D_reg_next;
  end

  always_comb begin
    D_xfer = D.val & D.rdy;
    W_xfer = W.val & W.rdy;

    if (D_xfer)
      D_reg_next = '{ val:1'b1, pc:D.pc, seq_num:D.seq_num,
                      op1:D.op1, op2:D.op2, waddr:D.waddr,
                      uop:D.uop, preg:D.preg, ppreg:D.ppreg };
    else if (W_xfer)
      D_reg_next = '0;
    else
      D_reg_next = D_reg;
  end

  // --------------------------------------------------------------------
  // Floating-point Add (IEEE-754 single)
  // --------------------------------------------------------------------
  logic [31:0] op1, op2;
  assign op1 = D_reg.op1;
  assign op2 = D_reg.op2;

  // Field extracts
  logic s1, s2;
  logic [7:0] e1, e2;
  logic [22:0] m1, m2;
  assign s1 = op1[31];
  assign e1 = op1[30:23];
  assign m1 = op1[22:0];
  assign s2 = op2[31];
  assign e2 = op2[30:23];
  assign m2 = op2[22:0];

  logic [26:0] a_sig, b_sig, sig_big, sig_small, sig_small_aln;
  logic [26:0] mask;
  logic [27:0] sum_ext, sig_norm_ext_next;
  logic [24:0] mant_sum;
  logic [7:0]  exp_big, exp_small, exp_norm_next, ediff;
  logic s_big, s_small, result_sign;

  logic guard, roundb, sticky, lsb, inc;
  logic sticky_align;
  logic sticky_norm;
  logic sticky_acc;
  logic right_shifted;  
  int   guard_pos;    
  int shift_adj;
  logic [23:0] mant_pre, mant_post;
  logic [22:0] final_mantissa;
  logic [7:0]  result_exp;
  int          shift_count;
  int base;


  always_comb begin
    // ------------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------------
    shift_count       = 0;
    sticky_acc = 1'b0;
    a_sig             = {1'b1, m1, 3'b000};
    b_sig             = {1'b1, m2, 3'b000};

    // Choose larger exponent/mantissa
    if (e1 > e2 || (e1 == e2 && a_sig >= b_sig)) begin
      exp_big   = e1; exp_small = e2;
      sig_big   = a_sig; sig_small = b_sig;
      s_big     = s1; s_small = s2;
    end else begin
      exp_big   = e2; exp_small = e1;
      sig_big   = b_sig; sig_small = a_sig;
      s_big     = s2; s_small = s1;
    end

    // Align smaller mantissa
    ediff = exp_big - exp_small;
    if (ediff >= 27) sig_small_aln = 0;
    else              sig_small_aln = sig_small >> ediff;

    // Bits lost during alignment → sticky_align
    mask = (ediff == 0) ? 27'b0 : ((27'b1 << ediff) - 27'b1);
    sticky_align = |(sig_small & mask);


    // ------------------------------------------------------------------
    // Add/Sub based on signs
    // ------------------------------------------------------------------
    if (s_big == s_small)
      sum_ext = {1'b0, sig_big} + {1'b0, sig_small_aln};
    else
      sum_ext = {1'b0, sig_big} - {1'b0, sig_small_aln};

    result_sign     = s_big;
    exp_norm_next   = exp_big;
    sig_norm_ext_next = sum_ext;

    // ------------------------------------------------------------------
    // Normalize
    // ------------------------------------------------------------------
    if (sig_norm_ext_next[27]) begin
      // overflow → shift right one
      sticky_align        = sticky_align | sig_norm_ext_next[0];
      sig_norm_ext_next   = sig_norm_ext_next >> 1;
      exp_norm_next++;
    end
    else begin
      while (sig_norm_ext_next[26] == 0 && sig_norm_ext_next != 0 && shift_count < 27) begin
        sig_norm_ext_next = sig_norm_ext_next << 1;
        exp_norm_next--;
        shift_count++;
      end
    end

    // ------------------------------------------------------------------
    // Guard / Round / Sticky dynamic positioning
    // ------------------------------------------------------------------

    shift_adj = right_shifted ? -1 : shift_count; // -1 if we right-shifted, +N if we left-shifted

    base = 2 + shift_adj;
    if (base < 2)
      base = 2;
    else if (base > 25)
      base = 25;

    sticky_norm = 1'b0;
    for (int i = 0; i <= (guard_pos-2); i++)
      sticky_norm |= sig_norm_ext_next[i];
    sticky = sticky_norm | sticky_align;

    guard  = sig_norm_ext_next[2];
    roundb = sig_norm_ext_next[1];
    sticky = sig_norm_ext_next[0] | sticky_align;  // include any aligned-dropped bits
    lsb    = sig_norm_ext_next[3];                 // == mant_pre[0]

    // ------------------------------------------------------------------
    // Round-to-nearest-even
    // ------------------------------------------------------------------
    inc = guard && (roundb || sticky || lsb);

    // 24-bit mantissa with hidden 1 at bit[23]
    mant_pre = sig_norm_ext_next[26:3];  // [23:0]

    // Do rounding in 25 bits to detect true overflow (carry out)
    mant_sum = {1'b0, mant_pre} + (inc ? 25'd1 : 25'd0);

    if (mant_sum[24]) begin
      // Overflow: becomes 1.000000... after shift; bump exponent
      mant_post      = mant_sum[24:1];   // keep it normalized
      exp_norm_next  = exp_norm_next + 8'd1;
    end else begin
      mant_post      = mant_sum[23:0];
    end

    final_mantissa = mant_post[22:0];    // drop the hidden 1
    result_exp     = exp_norm_next;
    result_sign    = s_big;

  end

  // --------------------------------------------------------------------
  // Operation select
  // --------------------------------------------------------------------
  rv_uop uop = D_reg.uop;
  always_comb begin
    unique case (uop)
      OP_ADD  : W.wdata = { result_sign, result_exp, final_mantissa };
      default : W.wdata = 'x;
    endcase
  end

  // --------------------------------------------------------------------
  // Handshake
  // --------------------------------------------------------------------
  assign D.rdy     = W.rdy | !D_reg.val;
  assign W.val     = D_reg.val;
  assign W.pc      = D_reg.pc;
  assign W.wen     = 1'b1;
  assign W.seq_num = D_reg.seq_num;
  assign W.waddr   = D_reg.waddr;
  assign W.preg    = D_reg.preg;
  assign W.ppreg   = D_reg.ppreg;

  // --------------------------------------------------------------------
  // Debug
  // --------------------------------------------------------------------
`ifndef SYNTHESIS
  always_ff @(posedge clk) if (W.val & W.rdy) begin
    $display("\n====================================================");
    $display("===  ALUF DEBUG (seq=%0d, uop=%s)  ===", D_reg.seq_num, D_reg.uop.name());
    $display("----------------------------------------------------");

    // Input operands
    $display("INPUTS:");
    $display("  op1_raw   = 0x%08h   op2_raw   = 0x%08h", D_reg.op1, D_reg.op2);
    $display("  exp_big   = %0d       exp_small = %0d   ediff = %0d", exp_big, exp_small, ediff);
    $display("  sign_big  = %b         sign_small = %b", s_big, s_small);
    $display("");

    // Aligned and summed significands
    $display("ALIGNMENT & ADDITION:");
    $display("  sum_ext        = 0x%08h   result_sign = %b", sum_ext, result_sign);
    $display("  sig_norm_ext   = 0x%08h   exp_norm_next = %0d", sig_norm_ext_next, exp_norm_next);
    $display("");

    // Guard, Round, Sticky, and rounding decision
    $display("ROUNDING INFO:");
    $display("  guard=%b  roundb=%b  sticky=%b  lsb=%b  inc=%b", guard, roundb, sticky, lsb, inc);
    $display("");

    // Mantissa state
    $display("MANTISSA STATE:");
    $display("  mant_pre  = 0x%08h", mant_pre);
    $display("  mant_post = 0x%08h", mant_post);
    if (mant_post[23])
      $display("  >> Mantissa overflow detected, exponent incremented <<");
    $display("");

    // Final result
    $display("FINAL PACK:");
    $display("  final_mantissa = 0x%08h", final_mantissa);
    $display("  result_exp     = %0d", result_exp);
    $display("  result_sign    = %b", result_sign);
    $display("  ==> FP32 Result = 0x%08h", W.wdata);
    $display("====================================================\n");
  end
`endif

  function int ceil_div_4(int val);
    return (val / 4) + ((val % 4) > 0 ? 1 : 0);
  endfunction

  int str_len;
  assign str_len = ceil_div_4(p_seq_num_bits) + 2 +
                   11 + 1 +
                   ceil_div_4(5) + 1 +
                   8 + 1 + 8 + 1 + 8;

  function string trace(int trace_level);
    string trace;
    if (W.val & W.rdy) begin
      if (trace_level > 0)
        trace = $sformatf("%h: %11s:%h:%h:%h:%h",
                          W.seq_num, D_reg.uop.name(),
                          W.waddr, op1, op2, W.wdata);
      else
        trace = $sformatf("%h", W.seq_num);
    end else begin
      if (trace_level > 0)
        trace = {str_len{" "}};
      else
        trace = {(ceil_div_4(p_seq_num_bits)){" "}};
    end
  endfunction

endmodule

`endif // HW_EXECUTE_EXECUTE_VARIANTS_L1_ALULF_V
