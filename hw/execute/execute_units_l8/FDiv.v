//========================================================================
// FDiv.v
//========================================================================
// Single-precision floating-point divider (FDIV.S).
//========================================================================

`ifndef HW_EXECUTE_EXECUTE_UNITS_L8_FDIV_V
`define HW_EXECUTE_EXECUTE_UNITS_L8_FDIV_V

`include "defs/UArch.v"
`include "intf/D__XIntf.v"
`include "intf/X__WIntf.v"

import UArch::*;

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
  // DIVIDE LOGIC-- PUT ALL UR WORK HERE SHEHROZE!!
  //----------------------------------------------------------------------

  localparam p_expwidth = 8;
  localparam p_frwidth  = 23;
  localparam p_opwidth  = 1 + p_expwidth + p_frwidth;

  // Registers for the calculation stage
  logic [24:0] rem;
  logic [24:0] divisor;
  logic [25:0] quotient;
  logic [4:0]  count;
  logic [24:0] next_rem;
  logic [25:0] next_quotient;
  logic        sticky;
  logic [p_expwidth-1:0] exp_calc;
  logic [p_expwidth-1:0] exp_reg;
  logic [p_expwidth-1:0] next_exp;
  logic [31:0] result;

  typedef enum {
    IDLE,
    UNPACK,
    CALC,
    NORMALIZE,
    ROUND,
    DONE
  } div_state_t;

  div_state_t curr_state;
  div_state_t next_state;
  logic calc_done;

  always_ff @( posedge clk ) begin
    if( rst )
      curr_state <= IDLE;
    else
      curr_state <= next_state;
  end
    //D_xfer tells us when a new instruction needs to be loaded in, W_xfer tells us when the output is ready receive.
  always_comb begin
    next_state = curr_state;
    case(curr_state) 
        IDLE: if(D_xfer) next_state = UNPACK;
        UNPACK: next_state = CALC; // We go directly just to the next stage CALC, as we only need 1 cycle to set up signals
        CALC: if(calc_done) next_state = NORMALIZE;
        NORMALIZE: next_state = ROUND;
        ROUND: next_state = DONE;
        DONE: begin
            if(W_xfer) begin
                if(D_xfer)
                    next_state = UNPACK; // prevents wasting a cycle as we can go directly to UNPACK
                else
                    next_state = IDLE;
            end
        end
    endcase
  end

  logic sn_dividend; // sign bits
  logic sn_divisor;
  logic [p_expwidth-1:0] exp_dividend; // exponent fields
  logic [p_expwidth-1:0] exp_divisor ;
  logic [p_frwidth-1:0]  fr_dividend ; // raw fraction bits, we haven't added the hidden 1 back yet.
  logic [p_frwidth-1:0]  fr_divisor  ;
  logic [p_frwidth:0] sig_dividend, sig_divisor;
  logic snR_unpack;

  always_comb begin
    if(curr_state == UNPACK) begin // Don't think we need this check, as these values won't latch if we aren't in UNPAC
            sn_dividend  = D_reg.op1[p_opwidth-1];
            sn_divisor   = D_reg.op2[p_opwidth-1];
            fr_dividend  = D_reg.op1[p_frwidth-1:0];
            fr_divisor   = D_reg.op2[p_frwidth-1:0];
            exp_dividend = D_reg.op1[p_opwidth-2 -: p_expwidth];
            exp_divisor  = D_reg.op2[p_opwidth-2 -: p_expwidth];
            sig_dividend = {1'b1, fr_dividend};
            sig_divisor  = {1'b1, fr_divisor};
            snR_unpack   = sn_dividend ^ sn_divisor;
    end
  end

  // Update the states of the calculation registers
  always_ff @(posedge clk) begin
      if ( rst ) begin
      rem      <= 25'b0;
      divisor  <= 25'b0;
      quotient <= 26'b0;
      count    <= 5'b0;
    end
    else if ( curr_state == UNPACK ) begin
      rem      <= {1'b0, sig_dividend};
      divisor  <= {1'b0, sig_divisor};
      quotient <= 26'b0;
      count    <= 5'b0;
      exp_reg  <= exp_calc;
    end
    else if ( curr_state == CALC ) begin
      rem      <= next_rem;
      quotient <= next_quotient;
      count    <= count + 1;
    end
    else if ( curr_state == NORMALIZE ) begin
      quotient <= next_quotient;
      exp_reg  <= next_exp;
    end
  end

  // Iterative significand division
  assign calc_done = (count == 5'd25);
  assign exp_calc = exp_dividend - exp_divisor + 8'd127; // Add back the exponent normalizaiton
  assign sticky = (rem != 25'b0); // Check the sticky bit
  always_comb begin
    next_rem = rem; // Default values
    next_quotient = quotient;
    if (curr_state == CALC) begin
       if(rem >= divisor) begin
          next_rem = (rem - divisor) << 1;
          next_quotient = {quotient[24:0], 1'b1};
       end
       else begin
          next_rem = rem << 1;
          next_quotient = {quotient[24:0], 1'b0};
       end
    end
  end

  // Our value should now be in between 0.5 and 2. If it is less than 1, we need to shift left by 1, and
  // decrement our exponenet value by one.
  // Our value is less than 1 if MSB is 0
  always_comb begin 
    if(curr_state == NORMALIZE) begin
      next_quotient = quotient;
      next_exp = exp_calc;
      if(quotient[25] == 1'b0) begin
        next_quotient = quotient << 1;
        next_exp = exp_calc - 1;
      end
    end
  end



  // Exceptions


  //----------------------------------------------------------------------
  // Outputs
  //----------------------------------------------------------------------

  assign D.rdy = W.rdy | !D_reg.val;
  assign W.val = D_reg.val;

  assign W.pc      = D_reg.pc;
  assign W.seq_num = D_reg.seq_num;
  assign W.waddr   = D_reg.waddr;
  assign W.preg    = D_reg.preg;
  assign W.ppreg   = D_reg.ppreg;
  assign W.is_fp   = D_reg.is_fp;
  assign W.wen     = 1'b1;
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
