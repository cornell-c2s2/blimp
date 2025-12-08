//========================================================================
// ALUF.v
//========================================================================
// Floating-point adder (IEEE-754 single precision) with dynamic
// normalization and round-to-nearest-even (REN) using guard/round/sticky.
// Based on the standard FP adder flow: exponent diff, alignment,
// add/sub, normalize, rounding, post-processing.
//
// Reference: 32-bit binary floating-point adder using IEEE 754 single
// precision format (flow: align -> add -> LOD -> normalize -> REN).
//
// Author: Sumaia Jewena
//========================================================================

`ifndef HW_EXECUTE_EXECUTE_VARIANTS_L1_ALUF_V
`define HW_EXECUTE_EXECUTE_VARIANTS_L1_ALUF_V

`include "defs/UArch.v"
`include "intf/D__XIntf.v"
`include "intf/X__WIntf.v"

import UArch::*;

module ALUF (
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
    if ( rst )
      D_reg <= '0;
    else
      D_reg <= D_reg_next;
  end

  always_comb begin
    D_xfer = D.val & D.rdy;
    W_xfer = W.val & W.rdy;

    if ( D_xfer ) begin
      D_reg_next = '{
        val   : 1'b1,
        pc    : D.pc,
        seq_num : D.seq_num,
        op1   : D.op1,
        op2   : D.op2,
        waddr : D.waddr,
        uop   : D.uop,
        preg  : D.preg,
        ppreg : D.ppreg
      };
    end
    else if ( W_xfer ) begin
      D_reg_next = '0;
    end
    else begin
      D_reg_next = D_reg;
    end
  end

  // --------------------------------------------------------------------
  // Floating-point Add (IEEE-754 single)
  // --------------------------------------------------------------------
  
  logic [31:0] op1, op2_raw, op2;
  assign op1     = D_reg.op1;
  assign op2_raw = D_reg.op2;

  // If FSUB, flip the sign-bit of operand 2 → op2 = op2 ^ 0x80000000
  always_comb begin
    if (D_reg.uop == OP_FSUB_S)
      op2 = {~op2_raw[31], op2_raw[30:0]};   // Toggle sign bit
    else
      op2 = op2_raw;
  end

  // Field extracts
  logic        s1, s2;
  logic [7:0]  e1, e2;
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
  logic is_inf1,  is_inf2;
  logic is_nan1,  is_nan2;
  logic is_denorm1, is_denorm2;

  assign is_zero1   = (e1 == 8'b0)  && (m1 == 23'b0);
  assign is_zero2   = (e2 == 8'b0)  && (m2 == 23'b0);
  assign is_inf1    = (e1 == 8'hFF) && (m1 == 23'b0);
  assign is_inf2    = (e2 == 8'hFF) && (m2 == 23'b0);
  assign is_nan1    = (e1 == 8'hFF) && (m1 != 23'b0);
  assign is_nan2    = (e2 == 8'hFF) && (m2 != 23'b0);
  assign is_denorm1 = (e1 == 8'b0)  && (m1 != 23'b0);
  assign is_denorm2 = (e2 == 8'b0)  && (m2 != 23'b0);

  // Significand setup (implicit bit handling) + 3 extra bits
  logic [26:0] a_sig, b_sig;
  logic [26:0] sig_big, sig_small, sig_small_aln;
  logic [26:0] mask;
  logic [27:0] sum_ext, sig_norm_ext;
  logic [24:0] mant_sum;
  logic [7:0]  exp_big, exp_small, exp_norm, ediff;
  logic        s_big, s_small, result_sign;

  // REN bits and rounding control
  logic guard, roundb, sticky, lsb, inc;
  logic sticky_align;

  logic [23:0] mant_pre, mant_post;
  logic [22:0] final_mantissa;
  logic [7:0]  result_exp;
  logic        overflow, underflow;
  logic [31:0] fp_result;

  // Local variables that need to be assigned in all paths
  logic [7:0]  adj_e1, adj_e2;
  logic [27:0] temp_sig;
  logic [7:0]  temp_exp;

  // --------------------------------------------------------------------
  // Main combinational logic
  // --------------------------------------------------------------------
  always_comb begin
    // Default assignments - ensure all variables are assigned
    mask              = 27'b0;
    sum_ext           = '0;
    sig_norm_ext      = '0;
    guard             = 1'b0;
    roundb            = 1'b0;
    sticky            = 1'b0;
    lsb               = 1'b0;
    inc               = 1'b0;
    mant_pre          = '0;
    mant_sum          = '0;
    mant_post         = '0;
    final_mantissa    = '0;
    result_exp        = '0;
    result_sign       = 1'b0;
    fp_result         = '0;

    sticky_align     = 1'b0;
    a_sig            = '0;
    b_sig            = '0;
    sig_big          = '0;
    sig_small        = '0;
    sig_small_aln    = '0;
    exp_big          = '0;
    exp_small        = '0;
    exp_norm         = '0;
    ediff            = '0;
    s_big            = 1'b0;
    s_small          = 1'b0;
    overflow         = 1'b0;
    underflow        = 1'b0;
    
    // Initialize local variables
    adj_e1 = e1;
    adj_e2 = e2;
    temp_sig = '0;
    temp_exp = '0;

    // Setup significands with implicit bit
    a_sig = is_denorm1 ? {1'b0, m1, 3'b000} : {1'b1, m1, 3'b000};
    b_sig = is_denorm2 ? {1'b0, m2, 3'b000} : {1'b1, m2, 3'b000};

    // Handle special cases first
    if (is_nan1 || is_nan2) begin
      fp_result = 32'h7FC0_0000; // quiet NaN
    end
    else if (is_inf1) begin
      if (is_inf2 && (s1 != s2)) begin
        fp_result = 32'h7FC0_0000; // inf - inf = NaN
      end else begin
        fp_result = {s1, 8'hFF, 23'b0}; // ±inf
      end
    end
    else if (is_inf2) begin
      fp_result = {s2, 8'hFF, 23'b0}; // ±inf
    end
    else if (is_zero1 && is_zero2) begin
      fp_result = {s1 & s2, 31'b0}; // signed zero
    end
    else if (is_zero1) begin
      fp_result = op2; // return b
    end
    else if (is_zero2) begin
      fp_result = op1; // return a
    end
    else begin
      // Normal operation path
      
      // Adjust denormal exponents
      adj_e1 = (is_denorm1 || is_zero1) ? 8'd1 : e1;
      adj_e2 = (is_denorm2 || is_zero2) ? 8'd1 : e2;
      
      // Choose larger exponent/mantissa
      if (adj_e1 > adj_e2 || (adj_e1 == adj_e2 && a_sig >= b_sig)) begin
          exp_big   = adj_e1; 
          exp_small = adj_e2;
          sig_big   = a_sig; 
          sig_small = b_sig;
          s_big     = s1; 
          s_small   = s2;
      end 
      else begin
          exp_big   = adj_e2; 
          exp_small = adj_e1;
          sig_big   = b_sig; 
          sig_small = a_sig;
          s_big     = s2; 
          s_small   = s1;
      end

      result_sign = s_big;

      // Align smaller significand
      ediff = exp_big - exp_small;

      if ( ediff >= 27 ) begin
        sig_small_aln = 27'b0;
        sticky_align  = |sig_small;
      end
      else begin
        sig_small_aln = sig_small >> ediff;
        mask         = (ediff == 0) ? 27'b0 : ((27'b1 << ediff) - 27'b1);
        sticky_align = |(sig_small & mask);
      end

      // Add/Subtract based on signs
      if ( s_big == s_small )
        sum_ext = {1'b0, sig_big} + {1'b0, sig_small_aln};
      else
        sum_ext = {1'b0, sig_big} - {1'b0, sig_small_aln};

      result_sign   = s_big;
      exp_norm      = exp_big;
      sig_norm_ext  = sum_ext;

      // Normalize
      if ( sig_norm_ext[27] ) begin
        // shift right 1, bit[0] becomes additional sticky
        sticky_align = sticky_align | sig_norm_ext[0];
        sig_norm_ext = sig_norm_ext >> 1;
        exp_norm     = exp_norm + 8'd1;
      end
      else begin
        // Shift left until bit[26] is 1 or sum_ext is zero
        temp_sig = sig_norm_ext;
        temp_exp = exp_norm;
        
        // Use a for loop for left normalization
        for (int i = 0; i < 27; i++) begin
          if ((temp_sig[26] == 1'b0) && (temp_sig != 28'b0)) begin
            temp_sig = temp_sig << 1;
            temp_exp = temp_exp - 8'd1;
          end
        end
        sig_norm_ext = temp_sig;
        exp_norm = temp_exp;
      end

      // Rounding (REN: Round to Nearest, Even)
      guard  = sig_norm_ext[2];                // g
      roundb = sig_norm_ext[1];                // r
      sticky = sticky_align | sig_norm_ext[0]; // s = global sticky
      lsb    = sig_norm_ext[3];                // current LSB of mantissa

      // IEEE-754 REN increment
      inc = guard & (roundb | sticky | lsb);

      // 24-bit mantissa before rounding
      mant_pre = sig_norm_ext[26:3];

      // Add increment in extended form (25 bits)
      mant_sum = {1'b0, mant_pre} + {{24{1'b0}}, inc};

      // Handle possible carry-out from rounding (re-normalize)
      if ( mant_sum[24] ) begin
        mant_post     = mant_sum[24:1];            // shift right 1
        result_exp    = exp_norm + 8'd1;
      end
      else begin
        mant_post     = mant_sum[23:0];
        result_exp    = exp_norm;
      end

      final_mantissa = mant_post[22:0];
      result_sign    = s_big;

      // Post-processing: overflow, underflow
      overflow  = (result_exp > 8'hFE);
      underflow = (result_exp < 8'h01);

      if (overflow) begin
        fp_result = {result_sign, 8'hFF, 23'b0}; // ±Inf
      end
      else if (underflow) begin
        fp_result = {result_sign, 8'h00, 23'b0}; // ±0 (underflow)
      end
      else begin
        fp_result = {result_sign, result_exp, final_mantissa};
      end
    end
  end

  // --------------------------------------------------------------------
  // Operation select
  // --------------------------------------------------------------------
  
  rv_uop uop = D_reg.uop;

  always_comb begin
    unique case ( uop )
      OP_FADD_S,
      OP_FSUB_S : W.wdata = fp_result;
      default   : W.wdata = 'x;
    endcase
  end

  // --------------------------------------------------------------------
  // Handshake - Single cycle operation
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
  // Trace utilities
  // --------------------------------------------------------------------
  function int ceil_div_4( int val );
    return (val / 4) + ((val % 4) > 0 ? 1 : 0);
  endfunction

  int str_len;
  assign str_len = ceil_div_4(p_seq_num_bits) + 2 +
                   11 + 1 +
                   ceil_div_4(5) + 1 +
                   8 + 1 + 8 + 1 + 8;

  function string trace( int trace_level );
    string tr;
    if ( W.val & W.rdy ) begin
      if ( trace_level > 0 )
        tr = $sformatf("%h: %11s:%h:%h:%h:%h",
                       W.seq_num, D_reg.uop.name(),
                       W.waddr, op1, op2, W.wdata);
      else
        tr = $sformatf("%h", W.seq_num);
    end
    else begin
      if ( trace_level > 0 )
        tr = {str_len{" "}};
      else
        tr = {(ceil_div_4(p_seq_num_bits)){" "}};
    end
    return tr;
  endfunction

endmodule

`endif // HW_EXECUTE_EXECUTE_VARIANTS_L1_ALUF_V
