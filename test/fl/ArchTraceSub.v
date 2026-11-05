`ifndef TEST_FL_ARCHTRACESUB_V
`define TEST_FL_ARCHTRACESUB_V

`include "types/ArchTrace.v"
`include "test/FLTestUtils.v"

module ArchTraceSub (
  input logic        clk,
  input arch_trace_t arch,
  input logic        val
);
  FLTestUtils t( .rst( 1'b0), .* );
  arch_trace_t dut;
  logic dut_val;
  logic waiting = 1'b0;

  initial begin
    if( $bits( arch_trace_t ) != ARCH_TRACE_BITS )
      $fatal( 1, "arch_trace_t width is %0d, expected %0d",
              $bits( arch_trace_t ), ARCH_TRACE_BITS );
  end

  task check_arch_trace( input arch_trace_t exp );
    waiting = 1'b1;
    do begin
      #2 begin
        dut = arch;
        dut_val = val;
      end
      @( posedge clk );
      #1;
    end while( !dut_val );
    `CHECK_EQ( dut.pc, exp.pc );
    `CHECK_EQ( dut.gen_regs_wen, exp.gen_regs_wen );
    if( exp.gen_regs_wen ) begin
      `CHECK_EQ( dut.gen_regs_waddr, exp.gen_regs_waddr );
      `CHECK_EQ( dut.gen_regs_wdata, exp.gen_regs_wdata );
    end
    `CHECK_EQ( dut.trap, exp.trap );
    if( exp.trap ) `CHECK_EQ( dut.trap_cause, exp.trap_cause );
    `CHECK_EQ( dut.redirect_valid, exp.redirect_valid );
    if( exp.redirect_valid ) `CHECK_EQ( dut.redirect_pc, exp.redirect_pc );
    `CHECK_EQ( dut.csr_action_valid, exp.csr_action_valid );
    if( exp.csr_action_valid ) begin
      `CHECK_EQ( dut.csr_cmd, exp.csr_cmd );
      if( exp.csr_cmd inside {3'd1, 3'd2, 3'd3} ) begin
        `CHECK_EQ( dut.csr_addr, exp.csr_addr );
        `CHECK_EQ( dut.csr_wdata, exp.csr_wdata );
      end
    end
    waiting = 1'b0;
  endtask

  task check_legacy(
    input logic [31:0] exp_pc,
    input logic  [4:0] exp_waddr,
    input logic [31:0] exp_wdata,
    input logic        exp_wen
  );
    waiting = 1'b1;
    do begin
      #2 begin
        dut = arch;
        dut_val = val;
      end
      @( posedge clk );
      #1;
    end while( !dut_val );
    `CHECK_EQ( dut.pc, exp_pc );
    `CHECK_EQ( dut.gen_regs_wen, exp_wen );
    if( exp_wen ) begin
      `CHECK_EQ( dut.gen_regs_waddr, exp_waddr );
      `CHECK_EQ( dut.gen_regs_wdata, exp_wdata );
    end
    waiting = 1'b0;
  endtask

  function string trace( int trace_level );
    if( val && waiting )
      trace = $sformatf("%08x:%b:%b", arch.pc, arch.gen_regs_wen, arch.trap);
    else if( val ) trace = "              X";
    else if( waiting ) trace = "               ";
    else trace = "              .";
  endfunction

  logic unused_trace_level;
  assign unused_trace_level = 1'b0;
endmodule

`endif // TEST_FL_ARCHTRACESUB_V
