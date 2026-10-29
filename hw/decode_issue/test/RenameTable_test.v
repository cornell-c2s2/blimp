//========================================================================
// RenameTable_test.v
//========================================================================
// A testbench for our rename table

`include "hw/decode_issue/RenameTable.v"
`include "intf/CommitNotif.v"
`include "intf/CompleteNotif.v"
`include "test/fl/TestCaller.v"
`include "test/fl/TestPub.v"
`include "test/TestUtils.v"

import TestEnv::*;

//========================================================================
// RenameTableTestSuite
//========================================================================
// A test suite for the rename table

module RenameTableTestSuite #(
  parameter p_suite_num     = 0,
  parameter p_num_phys_regs = 36
);

  localparam p_phys_addr_bits = $clog2( p_num_phys_regs );

  string suite_name = $sformatf("%0d: RenameTableTestSuite_%0d", 
                                p_suite_num, p_num_phys_regs);
  
  //----------------------------------------------------------------------
  // Setup
  //----------------------------------------------------------------------

  logic clk, rst;
  TestUtils t( .* );

  //----------------------------------------------------------------------
  // Instantiate design under test
  //----------------------------------------------------------------------

  logic                  [4:0] dut_alloc_areg;
  logic [p_phys_addr_bits-1:0] dut_alloc_preg;
  logic [p_phys_addr_bits-1:0] dut_alloc_ppreg;
  logic                        dut_alloc_en;
  logic                        dut_alloc_rdy;

  logic                  [4:0] dut_lookup_areg    [2];
  logic [p_phys_addr_bits-1:0] dut_lookup_preg    [2];
  logic                        dut_lookup_pending [2];
  logic                        dut_lookup_en      [2];

  CompleteNotif #(
    .p_phys_addr_bits (p_phys_addr_bits)
  ) complete_notif();

  CommitNotif #(
    .p_phys_addr_bits (p_phys_addr_bits)
  ) commit_notif();

  RenameTable #(
    .p_num_phys_regs (p_num_phys_regs)
  ) dut (
    .recover (1'b0),
    .alloc_areg  (dut_alloc_areg),
    .alloc_preg  (dut_alloc_preg),
    .alloc_ppreg (dut_alloc_ppreg),
    .alloc_en    (dut_alloc_en),
    .alloc_rdy   (dut_alloc_rdy),

    .lookup_areg    (dut_lookup_areg),
    .lookup_preg    (dut_lookup_preg),
    .lookup_en      (dut_lookup_en),
    .lookup_pending (dut_lookup_pending),

    .complete    (complete_notif),
    .commit      (commit_notif),
    .*
  );

  //----------------------------------------------------------------------
  // Allocation
  //----------------------------------------------------------------------

  typedef logic [4:0] t_alloc_call_msg;

  typedef struct packed {
    logic [p_phys_addr_bits-1:0] preg;
    logic [p_phys_addr_bits-1:0] ppreg;
  } t_alloc_ret_msg;

  t_alloc_ret_msg alloc_ret_msg;
  assign alloc_ret_msg.preg  = dut_alloc_preg;
  assign alloc_ret_msg.ppreg = dut_alloc_ppreg;

  TestCaller #(
    .t_call_msg (t_alloc_call_msg),
    .t_ret_msg  (t_alloc_ret_msg)
  ) alloc_caller (
    .call_msg (dut_alloc_areg),
    .ret_msg  (alloc_ret_msg),
    .en       (dut_alloc_en),
    .rdy      (dut_alloc_rdy),
    .*
  );

  t_alloc_ret_msg msg_from_alloc;

  task alloc(
    input logic                  [4:0] alloc_areg,
    input logic [p_phys_addr_bits-1:0] alloc_preg,
    input logic [p_phys_addr_bits-1:0] alloc_ppreg
  );
    msg_from_alloc.preg  = alloc_preg;
    msg_from_alloc.ppreg = alloc_ppreg;

    alloc_caller.call( alloc_areg, msg_from_alloc );
  endtask

  //----------------------------------------------------------------------
  // Lookup
  //----------------------------------------------------------------------

  typedef logic [4:0] t_lookup_call_msg;
  typedef struct packed {
    logic [p_phys_addr_bits-1:0] preg;
    logic                        pending;
  } t_lookup_ret_msg;

  t_lookup_ret_msg lookup_ret_msg [2];
  assign lookup_ret_msg[0].preg    = dut_lookup_preg   [0];
  assign lookup_ret_msg[0].pending = dut_lookup_pending[0];
  assign lookup_ret_msg[1].preg    = dut_lookup_preg   [1];
  assign lookup_ret_msg[1].pending = dut_lookup_pending[1];

  TestCaller #(
    .t_call_msg (t_lookup_call_msg),
    .t_ret_msg  (t_lookup_ret_msg)
  ) lookup_caller[2] (
    .call_msg (dut_lookup_areg),
    .ret_msg  (lookup_ret_msg),
    .en       (dut_lookup_en),
    .rdy      (1'b1),
    .*
  );

  t_lookup_ret_msg msg_from_lookup_0;
  t_lookup_ret_msg msg_from_lookup_1;

  task lookup_0(
    input logic                  [4:0] lookup_areg,
    input logic [p_phys_addr_bits-1:0] lookup_preg,
    input logic                        lookup_pending
  );
    msg_from_lookup_0.preg    = lookup_preg;
    msg_from_lookup_0.pending = lookup_pending;

    lookup_caller[0].call( lookup_areg, msg_from_lookup_0 );
  endtask

  task lookup_1(
    input logic                  [4:0] lookup_areg,
    input logic [p_phys_addr_bits-1:0] lookup_preg,
    input logic                        lookup_pending
  );
    msg_from_lookup_1.preg    = lookup_preg;
    msg_from_lookup_1.pending = lookup_pending;

    lookup_caller[1].call( lookup_areg, msg_from_lookup_1 );
  endtask

  //----------------------------------------------------------------------
  // Complete
  //----------------------------------------------------------------------

  typedef logic [p_phys_addr_bits-1:0] t_complete_msg;

  t_complete_msg complete_msg;
  assign complete_notif.preg    = complete_msg;
  assign complete_notif.waddr   = 'x;
  assign complete_notif.wdata   = 'x;
  assign complete_notif.wen     = 'x;

  logic  [4:0] unused_complete_waddr;
  logic [31:0] unused_complete_wdata;
  logic        unused_complete_wen;

  assign unused_complete_waddr   = complete_notif.waddr;
  assign unused_complete_wdata   = complete_notif.wdata;
  assign unused_complete_wen     = complete_notif.wen;

  TestPub #(
    t_complete_msg
  ) complete_pub (
    .msg (complete_msg),
    .val (complete_notif.val),
    .*
  );

  t_complete_msg msg_to_complete_pub;

  task complete(
    input logic [p_phys_addr_bits-1:0] preg
  );
    msg_to_complete_pub = preg;

    complete_pub.pub( msg_to_complete_pub );
  endtask

  //----------------------------------------------------------------------
  // Commit
  //----------------------------------------------------------------------

  typedef logic [p_phys_addr_bits-1:0] t_commit_msg;

  t_commit_msg commit_msg;
  assign commit_notif.ppreg = commit_msg;
  assign commit_notif.pc    = 'x;
  assign commit_notif.waddr = 'x;
  assign commit_notif.wdata = 'x;
  assign commit_notif.wen   = 'x;

  logic [31:0] unused_commit_pc;
  logic  [4:0] unused_commit_waddr;
  logic [31:0] unused_commit_wdata;
  logic        unused_commit_wen;

  assign unused_commit_pc    = commit_notif.pc;
  assign unused_commit_waddr = commit_notif.waddr;
  assign unused_commit_wdata = commit_notif.wdata;
  assign unused_commit_wen   = commit_notif.wen;

  TestPub #(
    t_commit_msg
  ) commit_pub (
    .msg (commit_msg),
    .val (commit_notif.val),
    .*
  );

  t_commit_msg msg_to_commit_pub;

  task commit(
    input logic [p_phys_addr_bits-1:0] ppreg
  );
    msg_to_commit_pub = ppreg;

    commit_pub.pub( msg_to_commit_pub );
  endtask

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------

  string trace;

  // verilator lint_off BLKSEQ
  always @( posedge clk ) begin
    #2;
    trace = "";

    trace = {trace, dut.trace( t.trace_level )};
    trace = {trace, " | "};
    trace = {trace, alloc_caller.trace( t.trace_level )};
    trace = {trace, " | "};
    trace = {trace, lookup_caller[0].trace( t.trace_level )};
    trace = {trace, " | "};
    trace = {trace, lookup_caller[1].trace( t.trace_level )};
    trace = {trace, " | "};
    trace = {trace, complete_pub.trace( t.trace_level )};
    trace = {trace, " | "};
    trace = {trace, commit_pub.trace( t.trace_level )};

    t.trace( trace );
  end
  // verilator lint_on BLKSEQ

  //----------------------------------------------------------------------
  // test_case_1_basic
  //----------------------------------------------------------------------

  task test_case_1_basic();
    t.test_case_begin( "test_case_1_basic" );
    if( !t.run_test ) return;

    //     areg preg ppreg
    alloc( 1,   32,  1 );

    //        areg preg pend
    lookup_0( 1,   32,  1 );
    lookup_1( 1,   32,  1 );

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // test_case_2_initial
  //----------------------------------------------------------------------
  // Verify the initial allocation

  task test_case_2_initial();
    t.test_case_begin( "test_case_2_initial" );
    if( !t.run_test ) return;

    for( int i = 0; i < 32; i = i + 1 ) begin
      lookup_0( 5'(i), p_phys_addr_bits'(i), 0 );
      lookup_1( 5'(i), p_phys_addr_bits'(i), 0 );
    end

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // test_case_3_capacity
  //----------------------------------------------------------------------
  // Verify the number of phys. registers that can be allocated at once

  localparam capacity = p_num_phys_regs - 32;
  int        capacity_num_to_check;
  assign     capacity_num_to_check = ( capacity > 31 ) ? 31 : capacity;

  task test_case_3_capacity();
    t.test_case_begin( "test_case_3_capacity" );
    if( !t.run_test ) return;

    for( int i = 1; i <= capacity_num_to_check; i = i + 1 ) begin
      alloc( 5'(i), 31 + p_phys_addr_bits'(i), p_phys_addr_bits'(i) );

      lookup_0( 5'(i), 31 + p_phys_addr_bits'(i), 1 );
      lookup_1( 5'(i), 31 + p_phys_addr_bits'(i), 1 );
    end

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // test_case_4_reuse
  //----------------------------------------------------------------------

  task test_case_4_reuse();
    t.test_case_begin( "test_case_4_reuse" );
    if( !t.run_test ) return;

    for( int i = 1; i <= capacity_num_to_check; i = i + 1 ) begin
      alloc( 5'(i), 31 + p_phys_addr_bits'(i), p_phys_addr_bits'(i) );

      complete( 31 + p_phys_addr_bits'(i) );
      commit( p_phys_addr_bits'(i) );

      // Can now re-use the ppreg
      alloc( 5'(i), p_phys_addr_bits'(i), 31 + p_phys_addr_bits'(i) );
    end

    t.test_case_end();
  endtask

  //----------------------------------------------------------------------
  // run_test_suite
  //----------------------------------------------------------------------

  task run_test_suite();
    t.test_suite_begin( suite_name );

    test_case_1_basic();
    test_case_2_initial();
    test_case_3_capacity();
    test_case_4_reuse();
  endtask
endmodule

//========================================================================
// RenameTable_test
//========================================================================

module RenameTable_test;
  RenameTableTestSuite #(1)     suite_1();
  RenameTableTestSuite #(2, 40) suite_2();
  RenameTableTestSuite #(3, 64) suite_3();

  int s;

  initial begin
    test_bench_begin( `__FILE__ );
    s = get_test_suite();

    if ((s <= 0) || (s == 1)) suite_1.run_test_suite();
    if ((s <= 0) || (s == 2)) suite_2.run_test_suite();
    if ((s <= 0) || (s == 3)) suite_3.run_test_suite();

    test_bench_end();
  end
endmodule
