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

  // --------------------------------------------------------------------
  // Special case detection
  // --------------------------------------------------------------------
  logic is_zero1, is_zero2;
  logic is_inf1, is_inf2;
  logic is_nan1, is_nan2;
  logic is_denorm1, is_denorm2;

  assign is_zero1   = (e1 == 8'b0)  && (m1 == 23'b0);
  assign is_zero2   = (e2 == 8'b0)  && (m2 == 23'b0);
  assign is_inf1    = (e1 == 8'hFF) && (m1 == 23'b0);
  assign is_inf2    = (e2 == 8'hFF) && (m2 == 23'b0);
  assign is_nan1    = (e1 == 8'hFF) && (m1 != 23'b0);
  assign is_nan2    = (e2 == 8'hFF) && (m2 != 23'b0);
  assign is_denorm1 = (e1 == 8'b0)  && (m1 != 23'b0);
  assign is_denorm2 = (e2 == 8'b0)  && (m2 != 23'b0);

  // Significand setup (implicit bit handling)
  logic [26:0] a_sig_pre, b_sig_pre;
  assign a_sig_pre = (is_denorm1) ? {1'b0, m1, 3'b000} : {1'b1, m1, 3'b000};
  assign b_sig_pre = (is_denorm2) ? {1'b0, m2, 3'b000} : {1'b1, m2, 3'b000};

  // Internal signals
  logic [26:0] a_sig, b_sig, sig_big, sig_small, sig_small_aln;
  logic [26:0] mask;
  logic [27:0] sum_ext, sig_norm_ext_next;
  logic [24:0] mant_sum;
  logic [7:0]  exp_big, exp_small, exp_norm_next, ediff;
  logic s_big, s_small, result_sign;
  logic guard, roundb, sticky, lsb, inc;
  logic sticky_align, sticky_norm;
  int   shift_count;
  logic [23:0] mant_pre, mant_post;
  logic [22:0] final_mantissa;
  logic [7:0]  result_exp;
  logic overflow, underflow;
  logic [31:0] fp_result;

  // --------------------------------------------------------------------
  // Main combinational logic
  // --------------------------------------------------------------------
  always_comb begin
    // ------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------
    shift_count = 0;
    a_sig = a_sig_pre;
    b_sig = b_sig_pre;

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

    // Sticky for lost bits during alignment
    mask = (ediff == 0) ? 27'b0 : ((27'b1 << ediff) - 27'b1);
    sticky_align = |(sig_small & mask);

    // ------------------------------------------------------------
    // Add/Subtract based on signs
    // ------------------------------------------------------------
    if (s_big == s_small)
      sum_ext = {1'b0, sig_big} + {1'b0, sig_small_aln};
    else
      sum_ext = {1'b0, sig_big} - {1'b0, sig_small_aln};

    result_sign       = s_big;
    exp_norm_next     = exp_big;
    sig_norm_ext_next = sum_ext;

    // ------------------------------------------------------------
    // Normalize
    // ------------------------------------------------------------
    if (sig_norm_ext_next[27]) begin
      // Overflow → shift right one
      sticky_align      = sticky_align | sig_norm_ext_next[0];
      sig_norm_ext_next = sig_norm_ext_next >> 1;
      exp_norm_next++;
    end else begin
      while (sig_norm_ext_next[26] == 0 && sig_norm_ext_next != 0 && shift_count < 27) begin
        sig_norm_ext_next = sig_norm_ext_next << 1;
        exp_norm_next--;
        shift_count++;
      end
    end

    // ------------------------------------------------------------
    // Rounding (Round to Nearest, Even)
    // ------------------------------------------------------------
    guard  = sig_norm_ext_next[2];
    roundb = sig_norm_ext_next[1];
    sticky = |sig_norm_ext_next[0];
    lsb    = sig_norm_ext_next[3];

    inc = (guard & (roundb | sticky | lsb));

    mant_pre = sig_norm_ext_next[26:3];
    mant_sum = {1'b0, mant_pre} + {{24{1'b0}}, inc};


    if (mant_sum[24]) begin
      mant_post     = mant_sum[24:1];
      exp_norm_next = exp_norm_next + 8'd1;
    end else begin
      mant_post     = mant_sum[23:0];
    end

    final_mantissa = mant_post[22:0];
    result_exp     = exp_norm_next;
    result_sign    = s_big;
  end

  // --------------------------------------------------------------------
  // Post-processing: overflow, underflow, NaN/Inf handling
  // --------------------------------------------------------------------
  assign overflow  = (result_exp > 8'hFE);
  assign underflow = (result_exp < 8'h01);

  assign fp_result =
    (is_nan1 || is_nan2) ? 32'h7FC00000 :       // quiet NaN
    (is_inf1 || is_inf2) ? {result_sign, 8'hFF, 23'b0} :
    (overflow)           ? {result_sign, 8'hFF, 23'b0} :
    (underflow)          ? {result_sign, 8'h00, 23'b0} :
    (is_zero1 && is_zero2)? {result_sign, 31'b0} :
                            {result_sign, result_exp, final_mantissa};

  // --------------------------------------------------------------------
  // Operation select
  // --------------------------------------------------------------------
  rv_uop uop = D_reg.uop;
  always_comb begin
    unique case (uop)
      OP_ADD  : W.wdata = fp_result;
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
  // Debug (unchanged)
  // --------------------------------------------------------------------
// --------------------------------------------------------------------
// Debug (improved readability and clarity)
// --------------------------------------------------------------------
// --------------------------------------------------------------------
// Debug (cleaned for Verilator)
// --------------------------------------------------------------------
`ifndef SYNTHESIS
  // Helper function: interpret 32-bit IEEE 754 float as real (for debug only)
  function real f32_to_real(input logic [31:0] bits);
    logic sign;
    logic [7:0]  exp;
    logic [22:0] frac;
    real mantissa;
    real result;

    sign = bits[31];
    exp  = bits[30:23];
    frac = bits[22:0];

    if (exp == 8'b0 && frac == 23'b0)
      result = 0.0;
    else if (exp == 8'hFF)
      result = 1.0/0.0;  // Inf/NaN placeholder for debug
    else begin
      mantissa = 1.0 + (frac / 8388608.0); // 2^23 = 8388608
      result   = mantissa * (2.0 ** (exp - 127));
    end

    if (sign == 1'b1)
      result = -result;

    return result;
  endfunction

  always_ff @(posedge clk) if (W.val & W.rdy) begin
    real f1, f2, fres;
    real expected, abs_err;

    f1   = f32_to_real(D_reg.op1);
    f2   = f32_to_real(D_reg.op2);
    fres = f32_to_real(W.wdata);

    $display("\n====================================================");
    $display("===  ALUF FLOATING-POINT ADD DEBUG  (seq=%0d)  ===", D_reg.seq_num);
    $display("----------------------------------------------------");

    // 1. Input operands
    $display("INPUTS:");
    $display("  op1_raw = 0x%08h  (%f)", D_reg.op1, f1);
    $display("  op2_raw = 0x%08h  (%f)", D_reg.op2, f2);
    $display("  sign1=%b exp1=%0d  sign2=%b exp2=%0d", s1, e1, s2, e2);
    $display("  mant1=0x%06h  mant2=0x%06h", m1, m2);
    $display("");

    // 2. Alignment info
    $display("ALIGNMENT:");
    $display("  exp_big=%0d  exp_small=%0d  ediff=%0d", exp_big, exp_small, ediff);
    $display("  sig_big = 0x%08h", sig_big);
    $display("  sig_small_aln = 0x%08h (after right-shift)", sig_small_aln);
    $display("");

    // 3. Add/Sub and Normalize
    $display("ADDITION / NORMALIZATION:");
    $display("  sum_ext = 0x%08h", sum_ext);
    $display("  normalized_sig = 0x%08h", sig_norm_ext_next);
    $display("  normalized_exp = %0d", exp_norm_next);
    $display("  result_sign = %b", result_sign);
    $display("");

    // 4. Rounding info
    $display("ROUNDING:");
    $display("  guard=%b round=%b sticky=%b lsb=%b inc=%b", guard, roundb, sticky, lsb, inc);
    $display("  mant_pre  = 0x%08h", mant_pre);
    $display("  mant_post = 0x%08h", mant_post);
    if (mant_sum[24])
      $display("  >> Mantissa overflow detected, exponent incremented <<");
    $display("");

    // 5. Final packed result
    $display("FINAL RESULT:");
    $display("  result_sign = %b", result_sign);
    $display("  result_exp  = %0d", result_exp);
    $display("  result_mant = 0x%06h", final_mantissa);
    $display("  Packed FP32 = 0x%08h", W.wdata);
    $display("  Result (decoded) = %f", fres);
    $display("");

    // 6. Reference comparison
    expected = f1 + f2;
    abs_err  = (fres > expected) ? (fres - expected) : (expected - fres);

    $display("EXPECTED (f1 + f2) = %f", expected);
    $display("ABSOLUTE ERROR     = %e", abs_err);

    if (abs_err < 1e-6)
      $display("✅  RESULT MATCHES EXPECTED VALUE");
    else
      $display("❌  RESULT MISMATCH");

    $display("====================================================\n");
  end
`endif



  // --------------------------------------------------------------------
  // Trace utilities
  // --------------------------------------------------------------------
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

