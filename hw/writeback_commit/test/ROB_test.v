//========================================================================
// ROB_test.v
//========================================================================
// A testbench for our ROB

`include "hw/writeback_commit/ROB.v"
`include "test/fl/TestCaller.v"
`include "test/TestUtils.v"

import TestEnv::*;

//========================================================================
// ROBTestSuite
//========================================================================
// A test suite for the ROB

module ROBTestSuite #(
  parameter p_suite_num = 0,
  parameter p_msg_bits  = 32,
  parameter p_depth     = 4
);

  localparam p_addr_bits = $clog2( p_depth );
  
  string suite_name = $sformatf("%0d: ROBTestSuite_%d_%0d", 
                                p_suite_num, p_msg_bits, p_depth);

  //----------------------------------------------------------------------
  // Setup
  //----------------------------------------------------------------------

  logic clk, rst;
  TestUtils t( .* );

  //----------------------------------------------------------------------
  // Instantiate design under test
  //----------------------------------------------------------------------

  logic [p_addr_bits-1:0] dut_ins_idx;
  logic [ p_msg_bits-1:0] dut_ins_msg;
  logic                   dut_ins_en;

  logic [p_addr_bits-1:0] dut_deq_idx;
  logic [ p_msg_bits-1:0] dut_deq_msg;
  logic                   dut_deq_en;
  logic                   dut_deq_rdy;

  ROB #(
    .p_msg_bits (p_msg_bits),
    .p_depth    (p_depth)
  ) dut (
    .clk     (clk),
    .rst     (rst),
    
    .ins_idx (dut_ins_idx),
    .ins_msg (dut_ins_msg),
    .ins_en  (dut_ins_en),

    .deq_idx (dut_deq_idx),
    .deq_msg (dut_deq_msg),
    .deq_en  (dut_deq_en),
    .deq_rdy (dut_deq_rdy)
  );

  //----------------------------------------------------------------------
  // Insertion
  //----------------------------------------------------------------------

  typedef struct packed {
    logic [ p_msg_bits-1:0] msg;
    logic [p_addr_bits-1:0] idx;
  } t_ins_msg;

  t_ins_msg ins_msg;

  assign dut_ins_msg = ins_msg.msg;
  assign dut_ins_idx = ins_msg.idx;

  // Unused output message
  logic unused_dut_ins_output;
  assign unused_dut_ins_output = 1'b1;

  TestCaller #(
    .t_call_msg (t_ins_msg),
    .t_ret_msg  (logic)
  ) ins_caller (
    .call_msg (ins_msg),
    .ret_msg  (unused_dut_ins_output),
    .en       (dut_ins_en),
    .rdy      (1'b1),
    .*
  );

  t_ins_msg msg_to_send;

  task send(
    logic [ p_msg_bits-1:0] msg,
    logic [p_addr_bits-1:0] idx
  );
    msg_to_send.msg = msg;
    msg_to_send.idx = idx;

    ins_caller.call(msg_to_send, 1'b1);
  endtask

  //----------------------------------------------------------------------
  // Dequeue
  //----------------------------------------------------------------------

  typedef struct packed {
    logic [ p_msg_bits-1:0] msg;
    logic [p_addr_bits-1:0] idx;
  } t_deq_msg;

  t_deq_msg deq_msg;

  assign deq_msg.msg = dut_deq_msg;
  assign deq_msg.idx = dut_deq_idx;

  // Unused input message
  logic unused_dut_deq_input;

  TestCaller #(
    .t_call_msg (logic), 
    .t_ret_msg  (t_deq_msg)
  ) deq_caller (
    .call_msg (unused_dut_deq_input),
    .ret_msg  (deq_msg),
    .en       (dut_deq_en),
    .rdy      (dut_deq_rdy),
    .*
  );

  t_deq_msg msg_to_recv;

  task recv(
    input logic [ p_msg_bits-1:0] msg,
    input logic [p_addr_bits-1:0] idx
  );
    msg_to_recv.msg = msg;
    msg_to_recv.idx = idx;

    deq_caller.call(1'bx, msg_to_recv);
  endtask

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------

  string trace;

  // verilator lint_off BLKSEQ
  always @( posedge clk ) begin
    #2;
    trace = "";

    trace = {trace, ins_caller.trace( t.trace_level )};
    trace = {trace, " | "};
    trace = {trace, dut.trace( t.trace_level )};
    trace = {trace, " | "};
    trace = {trace, deq_caller.trace( t.trace_level )};

    t.trace( trace );
  end
  // verilator lint_on BLKSEQ

  //----------------------------------------------------------------------
  // test_case_basic
  //----------------------------------------------------------------------

  task test_case_basic();
    t.test_case_begin( "test_case_basic" );
    if( !t.run_test ) return;

    fork
      //    msg         idx
      send( 'hdeadbeef, '0 );
      recv( 'hdeadbeef, '0 );
    join

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // test_case_capacity
  //----------------------------------------------------------------------

  task test_case_capacity();
    t.test_case_begin( "test_case_capacity" );
    if( !t.run_test ) return;

    for( int i = 0; i < p_depth; i = i + 1 ) begin
      send( p_msg_bits'(i), p_addr_bits'(i) );
    end

    for( int i = 0; i < p_depth; i = i + 1 ) begin
      recv( p_msg_bits'(i), p_addr_bits'(i) );
    end

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // test_case_out_of_order
  //----------------------------------------------------------------------

  task test_case_out_of_order();
    t.test_case_begin( "test_case_out_of_order" );
    if( !t.run_test ) return;

    fork
      begin
        //   ins_data    ins_tag
        send('hFFFFFFFF, 'h3);
        send('h87654321, 'h1);
        send('h00000000, 'h2);
        send('h12345678, 'h0);
      end

      begin
        //   deq_front_data
        recv('h12345678, 'h0);
        recv('h87654321, 'h1);
        recv('h00000000, 'h2);
        recv('hFFFFFFFF, 'h3);
      end
    join

    t.test_case_end();
  endtask
  
  task test_case_wraparound();
    t.test_case_begin("test_case_wraparound");
    if( !t.run_test ) return;

    // Fill ROB
    for (int i = 0; i < p_depth; i++)
      send(p_msg_bits'(i), p_addr_bits'(i));

    // Dequeue two
    recv(0, 0);
    recv(1, 1);

    // Reinsert into freed slots
    send('hAAAA, 0);
    send('hBBBB, 1);

    // Drain
    recv(2, 2);
    recv(3, 3);
    recv('hAAAA, 0);
    recv('hBBBB, 1);

    t.test_case_end();
  endtask


  //----------------------------------------------------------------------
  // run_test_suite
  //----------------------------------------------------------------------

  task run_test_suite();
    t.test_suite_begin( suite_name );

    test_case_basic();
    test_case_capacity();
    test_case_out_of_order();
    test_case_wraparound();
  endtask

endmodule

//========================================================================
// ROB_test
//========================================================================

module ROB_test;
  ROBTestSuite #(1) suite_1();

  int s;

  initial begin
    test_bench_begin( `__FILE__ );
    s = get_test_suite();

    if ((s <= 0) || (s == 1)) suite_1.run_test_suite();

    test_bench_end();
  end
endmodule
