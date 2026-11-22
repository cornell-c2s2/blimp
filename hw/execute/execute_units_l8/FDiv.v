//========================================================================
// FDiv.v
//========================================================================
// Single-precision floating-point divider (FDIV.S).
//
// Behavior:
//   - Round to nearest, ties to even
//   - Subnormal inputs are treated as zero, subnormal results flush to zero
//   - Any NaN input, 0/0 and inf/inf return the canonical NaN 7fc00000
//========================================================================

`ifndef HW_EXECUTE_EXECUTE_UNITS_L8_FDIV_V
`define HW_EXECUTE_EXECUTE_UNITS_L8_FDIV_V

`include "defs/UArch.v"
`include "intf/D__XIntf.v"
`include "intf/X__WIntf.v"

import UArch::*;


//------------------------------------------------------------------------
// FPRound
//------------------------------------------------------------------------
// Round to nearest even, fix up mantissa spillover, then check overflow
// and underflow. The exponent is a 10-bit SIGNED value so that negative
// (underflowing) and large (overflowing) exponents do not wrap.
//------------------------------------------------------------------------

module FPRound (
  input  logic               sign,
  input  logic signed [9:0]  exp,
  input  logic        [23:0] mant,     // HAS IMPLICIT 1
  input  logic               guard, round, sticky,
  output logic        [31:0] round_result
);
  // Guard  : MSB of the dropped bits (>= 0.5 ulp if 1)
  // Round  : 2nd MSB of the dropped bits (0.25 ulp)
  // Sticky : OR of every bit below round
  // Round up if guard && (round || sticky || lsb)   (lsb breaks exact ties)

  logic              increment;  // 1 = round up, 0 = drop the bits
  logic        [24:0] mant_sum;  // Mantissa after adding increment
  logic        [24:0] mant_post; // Mantissa after spillover adjustment
  logic signed [9:0]  exp_post;  // Exponent after spillover adjustment

  assign increment = guard && (round || sticky || mant[0]);
  assign mant_sum  = {1'b0, mant} + {24'b0, increment};

  always_comb begin
    exp_post  = exp;
    mant_post = mant_sum;

    if (mant_sum[24] == 1'b1) begin // spillover: 1.111.. + ulp = 10.000..
      mant_post = mant_sum >> 1;
      exp_post  = exp + 10'sd1;
    end

    // Both operands are signed, so these are signed compares
    if (exp_post > 10'sd254) begin
      round_result = {sign, 8'd255, 23'b0};   // overflow -> signed inf
    end
    else if (exp_post < 10'sd1) begin
      round_result = {sign, 8'd0, 23'b0};     // underflow -> signed zero
    end
    else begin
      round_result = {sign, exp_post[7:0], mant_post[22:0]};
    end
  end

endmodule


//------------------------------------------------------------------------
// FDiv
//------------------------------------------------------------------------

module FDiv (
  input  logic clk,
  input  logic rst,

  //----------------------------------------------------------------------
  // D <-> X Interface
  //----------------------------------------------------------------------

  D__XIntf.X_intf D,

  //----------------------------------------------------------------------
  // X <-> W Interface
  //----------------------------------------------------------------------

  X__WIntf.X_intf W
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
    logic                 [31:0] op1;
    logic                 [31:0] op2;
    logic                  [4:0] waddr;
    rv_uop                       uop;
    logic [p_phys_addr_bits-1:0] preg;
    logic [p_phys_addr_bits-1:0] ppreg;
    logic                        is_fp;
  } D_input;

  D_input D_reg, D_reg_next;
  logic   D_xfer, W_xfer;

  always_ff @( posedge clk ) begin
    if ( rst )
      D_reg <= '0;
    else
      D_reg <= D_reg_next;
  end

  always_comb begin
    D_xfer = D.val & D.rdy;
    W_xfer = W.val & W.rdy;

    if ( D_xfer )
      D_reg_next = '{
        val    : 1'b1,
        pc     : D.pc,
        seq_num: D.seq_num,
        op1    : D.op1,
        op2    : D.op2,
        waddr  : D.waddr,
        uop    : D.uop,
        preg   : D.preg,
        ppreg  : D.ppreg,
        is_fp  : D.is_fp
      };
    else if ( W_xfer )
      D_reg_next = '0;
    else
      D_reg_next = D_reg;
  end

  //----------------------------------------------------------------------
  // Divide logic
  //----------------------------------------------------------------------

  localparam p_expwidth = 8;
  localparam p_frwidth  = 23;
  localparam p_opwidth  = 1 + p_expwidth + p_frwidth;

  // Registers for the calculation stage
  //   quotient is 27 bits: bit 26 is the integer bit (1 if op1 >= op2),
  //   bits 25:0 are fraction bits. 27 iterations give us enough bits to
  //   still have a real round bit after a normalize shift.
  logic        [24:0] rem;
  logic        [24:0] divisor;
  logic        [26:0] quotient;
  logic         [4:0] count;
  logic        [24:0] next_rem;
  logic        [26:0] next_quotient;
  logic               sticky;

  // Exponents are 10-bit signed so under/overflow does not wrap
  logic signed [9:0]  exp_calc;
  logic signed [9:0]  exp_reg;
  logic signed [9:0]  next_exp_normalized;
  logic        [26:0] next_quotient_normalized;
  logic               sign_reg;
  logic        [31:0] result;

  // Special case handling signals
  logic        is_special_case;
  logic [31:0] special_result;
  logic        is_special_case_reg;
  logic [31:0] special_result_reg;

  typedef enum {
    IDLE,
    UNPACK,
    CALC,
    NORMALIZE,
    ROUND,
    DONE
  } div_state_t;

  div_state_t cur_state;
  div_state_t next_state;
  logic calc_done;

  always_ff @( posedge clk ) begin
    if( rst )
      cur_state <= IDLE;
    else
      cur_state <= next_state;
  end

  // D_xfer: a new instruction is loaded. W_xfer: the output was taken.
  always_comb begin
    next_state = cur_state;
    case(cur_state)
      IDLE: if(D_xfer) next_state = UNPACK;
      UNPACK: begin // special cases skip straight to DONE
        if(is_special_case)
          next_state = DONE;
        else
          next_state = CALC;
      end
      CALC:      if(calc_done) next_state = NORMALIZE;
      NORMALIZE: next_state = ROUND;
      ROUND:     next_state = DONE;
      DONE: begin
        if(W_xfer) begin
          if(D_xfer)
            next_state = UNPACK; // go directly to UNPACK, no wasted cycle
          else
            next_state = IDLE;
        end
      end
      default: next_state = IDLE;
    endcase
  end

  //----------------------------------------------------------------------
  // UNPACK: field extraction and special case detection
  //----------------------------------------------------------------------

  logic sn_dividend; // sign bits
  logic sn_divisor;
  logic [p_expwidth-1:0] exp_dividend;
  logic [p_expwidth-1:0] exp_divisor;
  logic [p_frwidth-1:0]  fr_dividend;
  logic [p_frwidth-1:0]  fr_divisor;
  logic [p_frwidth:0]    sig_dividend, sig_divisor;
  logic snR_unpack;

  logic nan_dividend, nan_divisor;
  logic inf_dividend, inf_divisor;
  logic zero_dividend, zero_divisor;

  // Special cases: NaN input, 0/0, inf/inf, x/0, inf/x, x/inf, 0/x
  // exp == 0 is treated as zero whatever the fraction is (subnormal
  // inputs are flushed to zero).
  always_comb begin
    // defaults for everything to avoid inferred latches
    sn_dividend     = 1'b0;
    sn_divisor      = 1'b0;
    fr_dividend     = '0;
    fr_divisor      = '0;
    exp_dividend    = '0;
    exp_divisor     = '0;
    sig_dividend    = '0;
    sig_divisor     = '0;
    snR_unpack      = 1'b0;
    nan_dividend    = 1'b0;
    nan_divisor     = 1'b0;
    inf_dividend    = 1'b0;
    inf_divisor     = 1'b0;
    zero_dividend   = 1'b0;
    zero_divisor    = 1'b0;
    is_special_case = 1'b0;
    special_result  = 32'b0;

    if(cur_state == UNPACK) begin
      sn_dividend  = D_reg.op1[p_opwidth-1];
      sn_divisor   = D_reg.op2[p_opwidth-1];
      fr_dividend  = D_reg.op1[p_frwidth-1:0];
      fr_divisor   = D_reg.op2[p_frwidth-1:0];
      exp_dividend = D_reg.op1[p_opwidth-2 -: p_expwidth];
      exp_divisor  = D_reg.op2[p_opwidth-2 -: p_expwidth];
      sig_dividend = {1'b1, fr_dividend};
      sig_divisor  = {1'b1, fr_divisor};
      snR_unpack   = sn_dividend ^ sn_divisor;

      nan_dividend  = (exp_dividend == 8'd255) && (fr_dividend != '0);
      nan_divisor   = (exp_divisor  == 8'd255) && (fr_divisor  != '0);
      inf_dividend  = (exp_dividend == 8'd255) && (fr_dividend == '0);
      inf_divisor   = (exp_divisor  == 8'd255) && (fr_divisor  == '0);
      zero_dividend = (exp_dividend == 8'd0);   // subnormals flush to zero
      zero_divisor  = (exp_divisor  == 8'd0);

      is_special_case = 1'b1;

      if (nan_dividend || nan_divisor)
        special_result = 32'h7FC0_0000;                      // NaN in -> canonical NaN
      else if (zero_dividend && zero_divisor)
        special_result = 32'h7FC0_0000;                      // 0 / 0
      else if (inf_dividend && inf_divisor)
        special_result = 32'h7FC0_0000;                      // inf / inf
      else if (zero_divisor)
        special_result = {snR_unpack, 8'd255, 23'b0};        // x / 0 -> signed inf
      else if (inf_dividend)
        special_result = {snR_unpack, 8'd255, 23'b0};        // inf / x -> signed inf
      else if (inf_divisor)
        special_result = {snR_unpack, 8'd0, 23'b0};          // x / inf -> signed zero
      else if (zero_dividend)
        special_result = {snR_unpack, 8'd0, 23'b0};          // 0 / x -> signed zero
      else
        is_special_case = 1'b0;
    end
  end

  //----------------------------------------------------------------------
  // CALC: iterative significand division (27 iterations)
  //----------------------------------------------------------------------

  assign calc_done = (count == 5'd26);
  // 10-bit signed: exp_a - exp_b + bias. Never wraps (range -126 .. 380).
  assign exp_calc  = $signed({2'b00, exp_dividend}) - $signed({2'b00, exp_divisor}) + 10'sd127;
  // Sticky: anything left in the remainder, or the extra bit below round
  assign sticky    = (rem != 25'b0) || quotient[0];

  always_comb begin
    next_rem      = rem;
    next_quotient = quotient;
    if (cur_state == CALC) begin
      if (rem >= divisor) begin
        next_rem      = (rem - divisor) << 1;
        next_quotient = {quotient[25:0], 1'b1};
      end
      else begin
        next_rem      = rem << 1;
        next_quotient = {quotient[25:0], 1'b0};
      end
    end
  end

  //----------------------------------------------------------------------
  // NORMALIZE: quotient is in [0.5, 2). If the integer bit is 0, shift
  // left one and decrement the exponent. The shifted-in 0 lands in the
  // sticky position, so it never creates a fake round bit.
  //----------------------------------------------------------------------

  always_comb begin
    next_quotient_normalized = quotient;
    next_exp_normalized      = exp_reg;
    if (cur_state == NORMALIZE) begin
      if (quotient[26] == 1'b0) begin
        next_quotient_normalized = quotient << 1;
        next_exp_normalized      = exp_reg - 10'sd1;
      end
    end
  end

  // Update the calculation registers
  always_ff @(posedge clk) begin
    if ( rst ) begin
      rem                 <= 25'b0;
      divisor             <= 25'b0;
      quotient            <= 27'b0;
      count               <= 5'b0;
      exp_reg             <= 10'sd0;
      sign_reg            <= 1'b0;
      is_special_case_reg <= 1'b0;
      special_result_reg  <= 32'b0;
    end
    else if ( cur_state == UNPACK ) begin
      rem                 <= {1'b0, sig_dividend};
      divisor             <= {1'b0, sig_divisor};
      quotient            <= 27'b0;
      count               <= 5'b0;
      exp_reg             <= exp_calc;
      sign_reg            <= snR_unpack;
      is_special_case_reg <= is_special_case;
      special_result_reg  <= special_result;
    end
    else if ( cur_state == CALC ) begin
      rem      <= next_rem;
      quotient <= next_quotient;
      count    <= count + 5'd1;
    end
    else if ( cur_state == NORMALIZE ) begin
      quotient <= next_quotient_normalized;
      exp_reg  <= next_exp_normalized;
    end
  end

  //----------------------------------------------------------------------
  // ROUND
  //----------------------------------------------------------------------

  logic [31:0] round_result;
  FPRound fp_round_inst (
    .sign         (sign_reg),
    .exp          (exp_reg),
    .mant         (quotient[26:3]),
    .guard        (quotient[2]),
    .round        (quotient[1]),
    .sticky       (sticky),
    .round_result (round_result)
  );

  // Final result selection
  always_comb begin
    if (is_special_case_reg)
      result = special_result_reg;
    else
      result = round_result;
  end

  //----------------------------------------------------------------------
  // Outputs
  //----------------------------------------------------------------------

  assign D.rdy = W_xfer || !D_reg.val;
  assign W.val = D_reg.val && (cur_state == DONE);

  assign W.pc      = D_reg.pc;
  assign W.seq_num = D_reg.seq_num;
  assign W.waddr   = D_reg.waddr;
  assign W.preg    = D_reg.preg;
  assign W.ppreg   = D_reg.ppreg;
  assign W.is_fp   = D_reg.is_fp;
  assign W.wen     = D_reg.val;
  assign W.wdata   = result;

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------

`ifndef SYNTHESIS
  function int ceil_div_4( int val );
    return (val / 4) + ((val % 4) > 0 ? 1 : 0);
  endfunction

  int str_len;
  assign str_len = ceil_div_4(p_seq_num_bits) + 2 + // seq_num
                   ceil_div_4(5)              + 1 + // waddr
                   8                          + 1 + // op1
                   8                          + 1 + // op2
                   8;                               // wdata

  function string trace( int trace_level );
    if ( W.val & W.rdy ) begin
      if ( trace_level > 0 )
        trace = $sformatf("%h:%h:%h:%h:%h", W.seq_num,
                          W.waddr, D_reg.op1, D_reg.op2, W.wdata);
      else
        trace = $sformatf("%h", W.seq_num);
    end else begin
      if ( trace_level > 0 )
        trace = {str_len{" "}};
      else
        trace = {(ceil_div_4(p_seq_num_bits)){" "}};
    end
  endfunction
`endif

endmodule

`endif // HW_EXECUTE_EXECUTE_UNITS_L8_FDIV_V
