//========================================================================
// fp_test_cases.v
//========================================================================
// Floating-point addition test cases for the ALULF (floating-point adder)
//========================================================================

task test_case_fp_basic();
  t.test_case_begin("test_case_fp_basic");
  if (!t.run_test) return;

  fork
    //====================================================================
    // Send Thread — drives FP add operations into DUT
    //====================================================================
    begin
      //   pc        seq_num  op1(hex)       op2(hex)       waddr  uop
      // 11.375 + 5.563 = 16.938
      send('h0000_0000, 0, 32'h41360001, 32'h40B2001B, 5'h1, OP_ADD);

      // 59.979 + 6.5 = 66.479
      send('h0000_0004, 1, 32'h426FBD05, 32'h40D00000, 5'h2, OP_ADD);

      // 1000.5 + 981.654 = 1982.154
      send('h0000_0008, 2, 32'h447A1000, 32'h44756DDB, 5'h3, OP_ADD);

      // 549.987 + 5.563 = 555.550
      send('h0000_000C, 3, 32'h44097F2B, 32'h40B20019, 5'h4, OP_ADD);
    end

    //====================================================================
    // Receive Thread — checks that DUT outputs the expected FP sums
    //====================================================================
    begin
      //   pc        seq_num  waddr  wdata(hex)     wen
      recv('h0000_0000, 0, 5'h1, 32'h4181CF39, 1); // 16.938
      recv('h0000_0004, 1, 5'h2, 32'h42854FDF, 1); // 66.479 (matches IEEE-754 rounding)
      recv('h0000_0008, 2, 5'h3, 32'h44F7A314, 1); // 1982.154
      recv('h0000_000C, 3, 5'h4, 32'h440B8C9E, 1); // 555.550
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// run_fp_test_cases
//----------------------------------------------------------------------

task run_fp_test_cases();
  test_case_fp_basic();
endtask

