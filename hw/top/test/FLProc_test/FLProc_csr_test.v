//========================================================================
// FLProc_csr_test.v
//========================================================================

`include "hw/top/test/FLProcTestHarness.v"

module FLProc_csr_test #();
  FLProcTestHarness h();

  //----------------------------------------------------------------------
  // Include test cases
  //----------------------------------------------------------------------

  `include "hw/top/test/test_cases/directed/csr_test_cases.v"

  //----------------------------------------------------------------------
  // run_tests
  //----------------------------------------------------------------------

  task run_tests();
    test_bench_begin( `__FILE__ );

    h.t.test_suite_begin( "FLProc_csr_test" );
    run_directed_csr_tests();

    test_bench_end();
  endtask

  initial run_tests();
endmodule
