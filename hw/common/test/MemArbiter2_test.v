//========================================================================
// MemArbiter2_test.v
//========================================================================
// A testbench for the 2-input memory arbiter
//
// Author: Sumaia Jewena
//========================================================================

`include "test/TestUtils.v"
`include "hw/common/MemArbiter2.v"
`include "intf/MemIntf.v"

import TestEnv::*;

//========================================================================
// MemArbiter2TestSuite
//========================================================================

module MemArbiter2TestSuite #(
  parameter p_suite_num = 0
);

  string suite_name = $sformatf("%0d: MemArbiter2TestSuite", p_suite_num);

  //----------------------------------------------------------------------
  // Setup
  //----------------------------------------------------------------------

  logic clk, rst;
  TestUtils t( .* );

  //----------------------------------------------------------------------
  // Interfaces
  //----------------------------------------------------------------------

  MemIntf mem0();
  MemIntf mem1();
  MemIntf mem_out();

  //----------------------------------------------------------------------
  // DUT
  //----------------------------------------------------------------------

  MemArbiter2 DUT (
    .clk     (clk),
    .rst     (rst),
    .mem0    (mem0),
    .mem1    (mem1),
    .mem_out (mem_out)
  );

  //----------------------------------------------------------------------
  // Simple shared memory model
  //----------------------------------------------------------------------
  // - Always ready after reset deasserts
  // - Returns accepted request message one cycle later

  logic resp_pending;
  logic [$bits(mem_out.resp_msg)-1:0] resp_msg_reg;

  assign mem_out.req_rdy = !rst;

  always_ff @(posedge clk) begin
    if (rst) begin
      mem_out.resp_val <= 1'b0;
      mem_out.resp_msg <= '0;
      resp_pending     <= 1'b0;
      resp_msg_reg     <= '0;
    end
    else begin
      mem_out.resp_val <= resp_pending;
      mem_out.resp_msg <= resp_msg_reg;

      if (mem_out.req_val & mem_out.req_rdy) begin
        resp_pending <= 1'b1;
        resp_msg_reg <= mem_out.req_msg;
      end
      else begin
        resp_pending <= 1'b0;
      end
    end
  end

  //----------------------------------------------------------------------
  // Helpers
  //----------------------------------------------------------------------

  task clear_inputs();
    mem0.req_val   = 1'b0;
    mem1.req_val   = 1'b0;
    mem0.resp_rdy  = 1'b1;
    mem1.resp_rdy  = 1'b1;
    mem0.req_msg   = '0;
    mem1.req_msg   = '0;
  endtask

  task check_req_route(
    input logic        mem0_val,
    input logic [31:0] mem0_addr,
    input logic        mem1_val,
    input logic [31:0] mem1_addr,
    input logic        exp_req_val,
    input logic [31:0] exp_req_addr,
    input logic        exp_mem0_rdy,
    input logic        exp_mem1_rdy
  );
    if ( !t.failed ) begin
      clear_inputs();

      mem0.req_val      = mem0_val;
      mem0.req_msg.op   = MEM_MSG_READ;
      mem0.req_msg.addr = mem0_addr;

      mem1.req_val      = mem1_val;
      mem1.req_msg.op   = MEM_MSG_READ;
      mem1.req_msg.addr = mem1_addr;

      #8;

      if ( t.verbose ) begin
        $display( "%3d: mem0_val=%b mem0_addr=%h | mem1_val=%b mem1_addr=%h || out_val=%b out_addr=%h",
                  t.cycles,
                  mem0.req_val, mem0.req_msg.addr,
                  mem1.req_val, mem1.req_msg.addr,
                  mem_out.req_val, mem_out.req_msg.addr );
      end

      `CHECK_EQ( mem_out.req_val, exp_req_val );
      if ( exp_req_val )
        `CHECK_EQ( mem_out.req_msg.addr, exp_req_addr );
      `CHECK_EQ( mem0.req_rdy, exp_mem0_rdy );
      `CHECK_EQ( mem1.req_rdy, exp_mem1_rdy );

      #2;
    end
  endtask

  task send_and_check_response(
    input logic        mem0_val,
    input logic [31:0] mem0_addr,
    input logic        mem1_val,
    input logic [31:0] mem1_addr,
    input logic        exp_mem0_resp_val,
    input logic        exp_mem1_resp_val,
    input logic [31:0] exp_resp_addr
  );
    if ( !t.failed ) begin
      clear_inputs();

      mem0.req_val      = mem0_val;
      mem0.req_msg.op   = MEM_MSG_READ;
      mem0.req_msg.addr = mem0_addr;

      mem1.req_val      = mem1_val;
      mem1.req_msg.op   = MEM_MSG_READ;
      mem1.req_msg.addr = mem1_addr;

      // Let request fire on the next rising edge
      #10;

      // Drop requests before checking the routed response
      mem0.req_val = 1'b0;
      mem1.req_val = 1'b0;

      #8;

      if ( t.verbose ) begin
        $display( "%3d: mem0_resp_val=%b mem1_resp_val=%b resp_addr=%h",
                  t.cycles,
                  mem0.resp_val,
                  mem1.resp_val,
                  mem_out.resp_msg.addr );
      end

      `CHECK_EQ( mem0.resp_val,         exp_mem0_resp_val );
      `CHECK_EQ( mem1.resp_val,         exp_mem1_resp_val );
      `CHECK_EQ( mem_out.resp_msg.addr, exp_resp_addr     );

      #2;
    end
  endtask

  //----------------------------------------------------------------------
  // test_case_1_mem0_only
  //----------------------------------------------------------------------

  task test_case_1_mem0_only();
    t.test_case_begin( "test_case_1_mem0_only" );
    if ( !t.run_test ) return;

    check_req_route(
      1'b1, 32'h00001000,
      1'b0, 32'h00002000,
      1'b1, 32'h00001000,
      1'b1, 1'b0
    );

    send_and_check_response(
      1'b1, 32'h00001000,
      1'b0, 32'h00002000,
      1'b1, 1'b0,
      32'h00001000
    );

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // test_case_2_mem1_only
  //----------------------------------------------------------------------

  task test_case_2_mem1_only();
    t.test_case_begin( "test_case_2_mem1_only" );
    if ( !t.run_test ) return;

    check_req_route(
      1'b0, 32'h00001000,
      1'b1, 32'h00002000,
      1'b1, 32'h00002000,
      1'b0, 1'b1
    );

    send_and_check_response(
      1'b0, 32'h00001000,
      1'b1, 32'h00002000,
      1'b0, 1'b1,
      32'h00002000
    );

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // test_case_3_mem1_priority
  //----------------------------------------------------------------------

  task test_case_3_mem1_priority();
    t.test_case_begin( "test_case_3_mem1_priority" );
    if ( !t.run_test ) return;

    check_req_route(
      1'b1, 32'h00001000,
      1'b1, 32'h00002000,
      1'b1, 32'h00002000,
      1'b0, 1'b1
    );

    send_and_check_response(
      1'b1, 32'h00001000,
      1'b1, 32'h00002000,
      1'b0, 1'b1,
      32'h00002000
    );

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // test_case_4_idle
  //----------------------------------------------------------------------

  task test_case_4_idle();
    t.test_case_begin( "test_case_4_idle" );
    if ( !t.run_test ) return;

    check_req_route(
      1'b0, 32'h00001000,
      1'b0, 32'h00002000,
      1'b0, 32'h00000000,
      1'b1, 1'b0
    );

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // run_test_suite
  //----------------------------------------------------------------------

  task run_test_suite();
    t.test_suite_begin( suite_name );

    clear_inputs();

    test_case_1_mem0_only();
    test_case_2_mem1_only();
    test_case_3_mem1_priority();
    test_case_4_idle();

  endtask

endmodule

//========================================================================
// MemArbiter2_test
//========================================================================

module MemArbiter2_test;

  MemArbiter2TestSuite #(1) suite_1();

  int s;

  initial begin
    test_bench_begin( `__FILE__ );
    s = get_test_suite();

    if ((s <= 0) || (s == 1)) suite_1.run_test_suite();

    test_bench_end();
  end

endmodule
