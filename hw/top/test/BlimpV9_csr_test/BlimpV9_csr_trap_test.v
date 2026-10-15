//========================================================================
// BlimpV9_csr_trap_test.v
//========================================================================

`include "hw/top/test/BlimpV9_csrTestHarness.v"

module BlimpV9_csrTestSuite_trap #(
  parameter p_suite_num     = 0,
  parameter p_opaq_bits     = 8,
  parameter p_seq_num_bits  = 5,
  parameter p_num_phys_regs = 36,

  parameter p_mem_send_intv_delay = 1,
  parameter p_mem_recv_intv_delay = 1
);
  string suite_name = $sformatf("%0d: BlimpV9_csrTestSuite_%0d_%0d_%0d_%0d", 
                                p_suite_num,
                                p_opaq_bits, p_seq_num_bits,
                                p_mem_send_intv_delay, p_mem_recv_intv_delay);
  BlimpV9_csrTestHarness #(
    .p_check_fl            (1),
    .p_opaq_bits           (p_opaq_bits),
    .p_seq_num_bits        (p_seq_num_bits),
    .p_num_phys_regs       (p_num_phys_regs),
    .p_mem_send_intv_delay (p_mem_send_intv_delay),
    .p_mem_recv_intv_delay (p_mem_recv_intv_delay)
  ) h();

  import "DPI-C" function bit fl_check_trap(
    input int unsigned pc,
    input int unsigned cause
  );

  task check_trap(
    input logic [31:0] pc,
    input logic [31:0] cause
  );
    if( !fl_check_trap( pc, cause ) )
      $fatal( 1, "ISS did not produce trap cause %0d at %h", cause, pc );

    // WCU L4 publishes a no-writeback tuple for the trapping instruction.
    // The legacy RTL trace has no trap/cause fields. Handler CSR reads
    // below verify the cause and saved PC through GPR writeback. Direct
    // event comparison needs RTL trap/cause fields and matching ISS DPI.
    // Bypass h.check_trace: the ISS trap step was already consumed above.
    h.inst_trace_sub.check_trace( pc, 'x, 'x, 0 );
  endtask

  `include "hw/top/test/test_cases/directed/trap_test_cases.v"
  task run_test_suite();
    h.t.test_suite_begin( suite_name );
    run_directed_trap_tests();
  endtask
endmodule

module BlimpV9_csr_trap_test;
  BlimpV9_csrTestSuite_trap #(1)                 suite_1();
  BlimpV9_csrTestSuite_trap #(2, 8, 5, 36, 1, 1) suite_2();
  BlimpV9_csrTestSuite_trap #(3, 4, 3, 33, 1, 1) suite_3();
  BlimpV9_csrTestSuite_trap #(4,32, 4, 50, 3, 1) suite_4();
  BlimpV9_csrTestSuite_trap #(5, 2, 2, 48, 1, 3) suite_5();
  BlimpV9_csrTestSuite_trap #(6, 4, 6, 42, 3, 3) suite_6();
  int s;

  initial begin
    test_bench_begin( `__FILE__ );
    s = get_test_suite();

    if ((s <= 0) || (s == 1)) suite_1.run_test_suite();
    if ((s <= 0) || (s == 2)) suite_2.run_test_suite();
    if ((s <= 0) || (s == 3)) suite_3.run_test_suite();
    if ((s <= 0) || (s == 4)) suite_4.run_test_suite();
    if ((s <= 0) || (s == 5)) suite_5.run_test_suite();
    if ((s <= 0) || (s == 6)) suite_6.run_test_suite();

    test_bench_end();
  end
endmodule
