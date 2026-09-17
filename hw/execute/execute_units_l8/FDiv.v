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
