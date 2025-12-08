//========================================================================
// fp_test_cases.v
//========================================================================
// Author: Sumaia Jewena
//========================================================================

`ifndef FP_TEST_CASES_V
`define FP_TEST_CASES_V

//----------------------------------------------------------------------
// test_case_fp_basic
//----------------------------------------------------------------------
// Integer addition test cases
//----------------------------------------------------------------------

task test_case_fp_basic();
  t.test_case_begin("test_case_fp_basic");
  if (!t.run_test) return;

  fork
    begin
      //   pc  seq_num op1     op2     waddr uop
      send('0, 0,      32'h3f800000,  32'h40000000,  5'h1, OP_FADD_S); // 1.0 + 2.0 = 3.0
      send('1, 1,      32'h40b00000,  32'h40100000,  5'h4, OP_FADD_S); // 5.5 + 2.25 = 7.75
      send('0, 2,      32'h41200000,  32'h3f000000,  5'h4, OP_FADD_S); // 10.0 + 0.5 = 10.5
      send('1, 3,      32'h42c80000,  32'h41a00000,  5'h2, OP_FADD_S); // 100.0 + 20.0 = 120.0
    end

    begin
      //   pc  seq_num waddr wdata        wen
      recv('0, 0,      5'h1,  32'h40400000, 1); // 3.0
      recv('1, 1,      5'h4,  32'h40f80000, 1); // 7.75
      recv('0, 2,      5'h4,  32'h41280000, 1); // 10.5
      recv('1, 3,      5'h2,  32'h42f00000, 1); // 120.0
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_fp_rounding
//----------------------------------------------------------------------

task test_case_fp_rounding();
  t.test_case_begin("test_case_fp_rounding");
  if (!t.run_test) return;

  fork
    begin
      // Checks rounding down (small additions)
      send('1, 5, 32'h3f800000, 32'h33800000, 5'h2, OP_FADD_S); // 1.0 + 2^-24
      send('1, 7, 32'h40000000, 32'h33800000, 5'h4, OP_FADD_S); // 2.0 + 2^-24
      
      // Checks rounding up
      send('0, 6, 32'h3f800000, 32'h34000000, 5'h3, OP_FADD_S); // 1.0 + 2^-23
      send('0, 0, 32'h3f800000, 32'h34a00000, 5'h1, OP_FADD_S); // 1.0 + 1.78813934e-7 = 1.000000178813934 (expected result but gets rounded up)
    end

    begin 
      // Checks rounding down (small additions)
      recv('1, 5, 5'h2, 32'h3f800000, 1); // 1.0
      recv('1, 7, 5'h4, 32'h40000000, 1); // 2.0 
      
      // Checks rounding up
      recv('0, 6, 5'h3, 32'h3f800001, 1); // 1.0000002384
      recv('0, 0, 5'h1, 32'h3f800002, 1); // 1.000000238418579 
    end
  join

  t.test_case_end();
endtask

task test_case_edge();
  t.test_case_begin("test_case_edge");
  if (!t.run_test) return;

  fork
    begin
      // Almost subtracting equal numbers
      send('0, 0, 32'h3f800000, 32'hbf7fffff, 5'h1, OP_FADD_S); // 1.0 + (-0.99999994)

      // One input dominates; tests right-shift alignment path
      send('1, 1, 32'h42c80000, 32'h00000001, 5'h4, OP_FADD_S); // 100.0 + 1e-20 

      // Mantissa overflow; normalization after addition pushes result to next exponent
      send('0, 2, 32'h3fc00000, 32'h3fc00000, 5'h4, OP_FADD_S); // 1.5 + 1.5

      // Mantisa underflow; forces left-shift normalization
      send('1, 3, 32'h00800000, 32'h00400000, 5'h2, OP_FADD_S); // smallest normals
    end

    begin
      // // Almost subtracting equal numbers
      recv('0, 0,      5'h1, 32'h33800000, 1); // ~2^-24

      // One input dominates; tests right-shift alignment path
      recv('1, 1,      5'h4, 32'h42c80000, 1); // 100.0 

      // Mantissa overflow
      recv('0, 2,      5'h4, 32'h40400000, 1); // 3.0

      // Mantissa underflow
      recv('1, 3,      5'h2, 32'h00c00000, 1);

    end
  join

t.test_case_end();
endtask

task test_case_subtraction();
  t.test_case_begin("test_case_subtraction");
  if (!t.run_test) return;

  fork
    begin
      send('0, 0, 32'h40F00000, 32'h40100000, 5'h1, OP_FSUB_S); // 7.5 - 2.25 = 5.25
    end

    begin
      recv('0, 0, 5'h1, 32'h40A80000, 1); // 5.25
    end
  join

t.test_case_end();
endtask

//----------------------------------------------------------------------
// run_fp_test_cases
//----------------------------------------------------------------------

task run_fp_test_cases();
  test_case_fp_basic();
  test_case_fp_rounding();
  test_case_edge();
  test_case_subtraction();
endtask

`endif // FP_TEST_CASES_V
