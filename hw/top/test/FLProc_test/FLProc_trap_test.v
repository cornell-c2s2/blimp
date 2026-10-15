//========================================================================
// FLProc_trap_test.v
//========================================================================

`include "hw/top/test/FLProcTestHarness.v"

module FLProc_trap_test #();
  FLProcTestHarness h();

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

  endtask

  //----------------------------------------------------------------------
  // Include test cases
  //----------------------------------------------------------------------

  `include "hw/top/test/test_cases/directed/trap_test_cases.v"

  //----------------------------------------------------------------------
  // run_tests
  //----------------------------------------------------------------------

  task run_tests();
    test_bench_begin( `__FILE__ );

    h.t.test_suite_begin( "FLProc_trap_test" );
    run_directed_trap_tests();

    test_bench_end();
  endtask

  initial run_tests();
endmodule
