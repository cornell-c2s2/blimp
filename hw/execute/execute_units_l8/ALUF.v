//========================================================================
// ALULF.v
//========================================================================
// An execute unit for performing floating point arithmetic operations

`ifndef HW_EXECUTE_EXECUTE_VARIANTS_L1_ALULF_V
`define HW_EXECUTE_EXECUTE_VARIANTS_L1_ALULF_V

`include "defs/UArch.v"
`include "intf/D__XIntf.v"
`include "intf/X__WIntf.v"

import UArch::*;

module ALULF (
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
  } D_input;

  D_input D_reg;
  D_input D_reg_next;
  logic   D_xfer;
  logic   W_xfer;

  // verilator lint_off ENUMVALUE

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
    else if ( W_xfer )
      D_reg_next = '0;
    else
      D_reg_next = D_reg;
  end

  // verilator lint_on ENUMVALUE

  //----------------------------------------------------------------------
  // Arithmetic Operations
  //----------------------------------------------------------------------
  
  logic [31:0] op1, op2;
  assign op1 = D_reg.op1;
  assign op2 = D_reg.op2;

  // Op1 floating point
  logic op1_s = op1[31];
  logic [7:0] op1_exp = op1[30:23];
  logic [22:0] op1_mant = op1[22:0];

  // Op2 floating point
  logic op2_s = op2[31];
  logic [7:0] op2_exp = op2[30:23];
  logic [22:0] op2_mant = op2[22:0];

  // STEP 1: Align the exponents

  logic sign_diff;
  logic [22:0] op1_mant_shifted, op2_mant_shifted;
  logic [23:0] mant1_f, mant2_f;
  logic [24:0] mant_sum; // 25 bit for rounding

  logic [7:0]  exp_diff, exp_large, result_exp;

  logic result_sign;

  always_comb begin

  // exponent difference + sign_diff based on which exp is smaller

  // assign defailt values so the "final" mantissas are always defined
  exp_diff = 0;
  op1_mant_shifted = op1_mant;
  op2_mant_shifted = op2_mant;
  
  if (op1_exp > op2_exp) begin
    exp_diff = op1_exp - op2_exp;
    op2_mant_shifted = op2_mant >> exp_diff;
    exp_large = op1_exp;
  end
  else begin
    exp_diff = op2_exp - op1_exp;
    op1_mant_shifted = op1_mant >> exp_diff;
    exp_large = op2_exp;
  end

  

  // attaching the implicit "1" bit on mantissa, may need to move this elsewhere?
  mant1_f = {1'b1, op1_mant_shifted};
  mant2_f = {1'b1, op2_mant_shifted};

  // STEP 2: Addition/Subtraction
  

    if (op1_s == op2_s) begin // Same sign, simple addition
      mant_sum = {1'b0, mant1_f} + {1'b0, mant2_f};
      result_sign = op1_s;
    end

    else begin // Different sign,, (+A) + (-B) or (-A) + (+B)
      if (mant1_f >= mant2_f) begin // checking magnitiudes, to determine the sign of final sum
        mant_sum = {1'b0, mant1_f} - {1'b0, mant2_f};
        result_sign = op1_s;
      end
      else begin
        mant_sum = {1'b0, mant2_f} - {1'b0, mant1_f};
        result_sign = op2_s;
      end
      result_exp = exp_large;
    end

  

  // STEP 3: Normalization
  // Need to normalize again after adding/subtracting due to potential carry-out results, or producing leading zeroes
  // ex: mant_sum = 11.000000 * 2^5 if op1 = 1.111000 * 2^5; op2 = 1.001000 * 2^5
  // as u can see u need to normalize again
  // ex w sub: mant_sum = 0.000001 * 2^5 if op1 = 1.000000 * 2^5; op2 = 0.111111 * 2^5
  // need to shift to the right to put in form 1.xxxx
  
  

    if ( mant_sum[24] == 1 ) begin // when the overflow bit that was assigned 0, actually overflows to 1
      mant_sum = mant_sum >> 1;
      result_exp = result_exp + 1;
      end
    else begin // checking for leading 0's producted by subtraction
      while (mant_sum[23] == 0 && result_exp > 0 ) begin
        mant_sum = mant_sum << 1;
        result_exp = result_exp - 1;
      end
    end

  end

  // STEP 4: Rounding, bc mantissa is currently 25 bits
  
  logic [22:0] final_mantissa;
  assign final_mantissa = mant_sum[22:0]; // simple truncation

  // STEP 5: Concatenation (Assembiling sign, mantissa, and exp)

  logic [31:0] result;
  assign result = { result_sign, result_exp[7:0], final_mantissa };

  //W.wdata = result; // do we need?

  // 

  rv_uop uop;
  assign uop = D_reg.uop;

  always_comb begin
    case( uop )
      OP_ADD:  W.wdata = op1 + op2;
      default: W.wdata = 'x;
    endcase
  end


  //----------------------------------------------------------------------
  // Assign remaining signals
  //----------------------------------------------------------------------

  assign D.rdy = W.rdy | (!D_reg.val);
  assign W.val = D_reg.val;

  assign W.pc      = D_reg.pc;
  assign W.wen     = 1'b1;
  assign W.seq_num = D_reg.seq_num;
  assign W.waddr   = D_reg.waddr;
  assign W.preg    = D_reg.preg;
  assign W.ppreg   = D_reg.ppreg;

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------

`ifndef SYNTHESIS
  function int ceil_div_4( int val );
    return (val / 4) + ((val % 4) > 0 ? 1 : 0);
  endfunction

  int str_len;
  assign str_len = ceil_div_4(p_seq_num_bits) + 2 + // seq_num
                   11                         + 1 + // uop
                   ceil_div_4(5)              + 1 + // waddr
                   8                          + 1 + // op1
                   8                          + 1 + // op2
                   8;                               // wdata

  function string trace( int trace_level );
    if( W.val & W.rdy ) begin
      if( trace_level > 0 )
        trace = $sformatf("%h: %11s:%h:%h:%h:%h", W.seq_num, D_reg.uop.name(), 
                          W.waddr, op1, op2, W.wdata );
      else
        trace = $sformatf("%h", W.seq_num);
    end else begin
      if( trace_level > 0 )
        trace = {str_len{" "}};
      else
        trace = {(ceil_div_4(p_seq_num_bits)){" "}};
    end
  endfunction
`endif

endmodule

`endif // HW_EXECUTE_EXECUTE_VARIANTS_L1_ALUL1_V

