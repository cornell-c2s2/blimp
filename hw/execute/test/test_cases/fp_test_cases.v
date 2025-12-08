//========================================================================
// fp_test_cases.v
//========================================================================
// Floating-point addition test cases for the ALULF (floating-point adder)
//========================================================================

//1.(fraction) 8 2^(exponent-127). unsigned exponent. all exponent bits 1 = inf, 
//all exponent bits = 0 => 0 or subnormal
//fraction also in form of 2^-x
//fraction upto 2^-23
//0.0000000000000456 -> 
//u find first one and see the actual exponent uptill 127, then add bias to it to get stored expo
//then after adding bias u get the stored expo. fraction is jus the remaining bits
//when adding, u need to shift them back to match the expo's and then jus add mantissa and add back expo to the answer.
//when adding - u use grs to see the shifted out bits, then add a 26 bit mantissa to each other and if mantissa overflow
//then normalize it back.

//exponent - different sizes with diff sizes pairs - big pos, big neg, small pos, small neg
//subnormal numbers + subnormal - normal and subnormal, pos-pos = sub, sub - sub smaller than smallest - underflow.
//positive with negative giving positive, negative and zero
//grs = all combos
//overflow into inf
//inf + inf = 0, pos + pos = inf
//nan + num = nan

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
// task test_case_fp_subnorma();
//   t.test_case_begin("test_fp_subnormal");
//   if(!t.run_test) return;

//   fork
//     begin
     
//       //   pc        seq_num  op1(hex)       op2(hex)  waddr  uop
//       // normal positive + normal negative = subnormal
//       // 1.00000000e−38 − 0.99999994e−38 = 6e−46  (subnormal)
//       send('h0000_0010, 0, 32'h0C2CF0C0, 32'h8C2CF0BC, 5'h1, OP_ADD);
//       //subnormal + subnormal = subnormal
//       // 3e-45 + 2e-45 = 5e-45
//       send('h0000_0014, 1, 32'h00000003, 32'h00000002, 5'h2, OP_ADD);
//       //subnomral + subnormal = normal
//       // 1.0e-38 (large subnormal) + 1.0e-38 = 2.0e-38 (normal)
//       send('h0000_0018, 2, 32'h007FFFFF, 32'h007FFFFF, 5'h3, OP_ADD);

//     end

//     begin
//       recv('h0000_0010, 0, 5'h1, 32'h00000004, 1); // subnormal ≈ 6e−46
//       recv('h0000_0014, 1, 5'h2, 32'h00000005, 1); // 5e−45 subnormal
//       recv('h0000_0018, 2, 5'h3, 32'h00800000, 1); // normalized 2.0e−38
//     end
//   join
//   t.test_case_end();
// endtask

// task test_case_fp_normal();
// t.test_case_begin("t_fp_pos_neg");
//   if(!t.run_test) return;

//   fork
//     begin
     
//       //   pc        seq_num  op1(hex)       op2(hex)  waddr  uop
//       // pos (10.5) + neg (−2.25) = 8.25
//       send('h0000_0020, 0, 32'h41280000, 32'hC0200000, 5'h1, OP_ADD);

//       // pos (3.0) + neg (−10.0) = −7.0
//       send('h0000_0024, 1, 32'h40400000, 32'hC1200000, 5'h2, OP_ADD);

//       // pos (5.0) + neg (−5.0) = 0.0
//       send('h0000_0028, 2, 32'h40A00000, 32'hC0A00000, 5'h3, OP_ADD);
      
//     end

//     begin
//       recv('h0000_0020, 0, 5'h1, 32'h41040000, 1); // 8.25
//       recv('h0000_0024, 1, 5'h2, 32'hC0E00000, 1); // −7.0
//       recv('h0000_0028, 2, 5'h3, 32'h00000000, 1); // +0.0
//     end
//   join

//   t.test_case_end();

// t.test_case_begin("test_case_fp_grs_bits");
//   if (!t.run_test) return;

//   fork
//     //====================================================================
//     // Send Thread
//     //====================================================================
//     begin
//       //------------------------------------------------------------------
//       // BASELINE: 1.0 (0x3F800000)
//       // Exponent = 127.
//       // We vary Op2 to shift bits into GRS positions.
//       //------------------------------------------------------------------

//       // 1. GRS = 000 (Exact fit, no rounding)
//       // 1.0 + 1.0*2^-10 (Shift 10) -> Fits inside 23-bit mantissa
//       // Exp: 127-10 = 117 (0x75) -> 0x3A800000
//       send('h0000_0030, 0, 32'h3F800000, 32'h3A800000, 5'h1, OP_ADD);

//       // 2. GRS = 010 (Guard=0, Round=1, Sticky=0) -> Round Down (Truncate)
//       // 1.0 + 1.0*2^-25 (Shift 25)
//       // Exp: 127-25 = 102 (0x66) -> 0x33000000
//       send('h0000_0034, 1, 32'h3F800000, 32'h33000000, 5'h2, OP_ADD);

//       // 3. GRS = 011 (Guard=0, Round=1, Sticky=1) -> Round Up
//       // 1.0 + (1.0 + epsilon)*2^-25
//       // We use 0x33000001 so the LSB contributes to Sticky
//       send('h0000_0038, 2, 32'h3F800000, 32'h33000001, 5'h3, OP_ADD);

//       //------------------------------------------------------------------
//       // TIE-BREAKING CASES (Guard=1, Round=0, Sticky=0)
//       //------------------------------------------------------------------

//       // 4. GRS = 100, LSB=0 (Tie -> Round to Even -> Stay 0)
//       // Op1: 1.5 (0x3FC00000) - LSB is 0
//       // Op2: 1.0*2^-24 (Shift 24 relative to 1.5's Exp 127)
//       // Exp: 127-24 = 103 (0x67) -> 0x33800000
//       send('h0000_003C, 3, 32'h3FC00000, 32'h33800000, 5'h4, OP_ADD);

//       // 5. GRS = 100, LSB=1 (Tie -> Round to Even -> Round Up +1)
//       // Op1: 1.5 + 1ULP (0x3FC00001) - LSB is 1
//       // Op2: Same as above (0x33800000)
//       send('h0000_0040, 4, 32'h3FC00001, 32'h33800000, 5'h5, OP_ADD);

//       //------------------------------------------------------------------
//       // REMAINING COMBINATIONS
//       //------------------------------------------------------------------

//       // 6. GRS = 101 (Guard=1, Sticky=1) -> Round Up
//       // Shift 24. Op2 needs sticky bit. 0x33800001
//       send('h0000_0044, 5, 32'h3F800000, 32'h33800001, 5'h6, OP_ADD);

//       // 7. GRS = 110 (Guard=1, Round=1) -> Round Up
//       // Shift 24. We need Mantissa 0.5 (Binary 1.1)
//       // Op2: 1.5 * 2^-24. Hex 0x33C00000
//       send('h0000_0048, 6, 32'h3F800000, 32'h33C00000, 5'h7, OP_ADD);

//       // 8. GRS = 111 (All 1s) -> Round Up
//       // Shift 24. Mantissa 0.5 + epsilon. 0x33C00001
//       send('h0000_004C, 7, 32'h3F800000, 32'h33C00001, 5'h8, OP_ADD);
//     end

//     //====================================================================
//     // Receive Thread
//     //====================================================================
//     begin
//       // 1. GRS=000
//       recv('h0000_0030, 0, 5'h1, 32'h3F800400, 1); // Exact sum

//       // 2. GRS=010 (Round Down)
//       recv('h0000_0034, 1, 5'h2, 32'h3F800000, 1); // Stays 1.0

//       // 3. GRS=011 (Round Up)
//       recv('h0000_0038, 2, 5'h3, 32'h3F800001, 1); // 1.0 + 1ulp

//       // 4. GRS=100, LSB=0 (Tie -> Even)
//       recv('h0000_003C, 3, 5'h4, 32'h3FC00000, 1); // Stays 1.5

//       // 5. GRS=100, LSB=1 (Tie -> Even -> Up)
//       recv('h0000_0040, 4, 5'h5, 32'h3FC00002, 1); // 1.5...1 -> 1.5...2

//       // 6. GRS=101 (Round Up)
//       recv('h0000_0044, 5, 5'h6, 32'h3F800001, 1);

//       // 7. GRS=110 (Round Up)
//       recv('h0000_0048, 6, 5'h7, 32'h3F800001, 1);

//       // 8. GRS=111 (Round Up)
//       recv('h0000_004C, 7, 5'h8, 32'h3F800001, 1);
//     end
//   join
//   t.test_case_end();

//   t.test_case_begin("t_fp_exponent differences");
//   if(!t.run_test) return;

//   fork
//     begin
     
//       //   pc        seq_num  op1(hex)       op2(hex)  waddr  uop
//       // large exp diff: 2^125 + 2^5 ≈ 2^125 (alignment drop)
//       send('h0000_0050, 0, 32'h5E800000, 32'h41000000, 5'h1, OP_ADD);
//       // exps 23 vs 56
//       send('h0000_0054, 1, 32'h4B000000, 32'h4E800000, 5'h2, OP_ADD);
//       // exps 1 vs 100
//       send('h0000_0058, 2, 32'h3F800000, 32'h57000000, 5'h3, OP_ADD);
//       // equal exps : no alignment shift
//       send('h0000_005C, 3, 32'h41C00000, 32'h41A00000, 5'h4, OP_ADD);      
//     end

//     begin
//       recv('h0000_0050, 0, 5'h1, 32'h5E800000, 1);
//       recv('h0000_0054, 1, 5'h2, 32'h4E800000, 1);
//       recv('h0000_0058, 2, 5'h3, 32'h57000000, 1);
//       recv('h0000_005C, 3, 5'h4, 32'h42300000, 1); // 24.0 + 20.0 = 44.0

//     end
//   join

//   t.test_case_end();
// endtask



// task test_case_fp_extremes();
// t.test_case_begin("t_fp_overflow");
//   if(!t.run_test) return;

//   fork
//     begin
     
//       //   pc        seq_num  op1(hex)       op2(hex)  waddr  uop
//       // max normal + max normal → +inf
//       send('h0000_0060, 0, 32'h7F7FFFFF, 32'h7F7FFFFF, 5'h1, OP_ADD);
//     end

//     begin
//       recv('h0000_0060, 0, 5'h1, 32'h7F800000, 1); // +inf
//     end
//   join

//   t.test_case_end();

// t.test_case_begin("t_fp_underflow");
//   if(!t.run_test) return;

//   fork
//     begin
//       //   pc        seq_num  op1(hex)       op2(hex)  waddr  uop
//       // smallest negative subnormal + smallest negative subnormal -> underflow -> −0.0
//       send('h0000_0064, 0, 32'h807FFFFF, 32'h807FFFFF, 5'h1, OP_ADD);
//     end

//     begin
//       recv('h0000_0064, 0, 5'h1, 32'h80000000, 1); // −0.0
//     end
//   join

//   t.test_case_end();

//   t.test_case_begin("t_fp_nan");
//   if(!t.run_test) return;

//   fork
//     begin
     
//       //   pc        seq_num  op1(hex)       op2(hex)  waddr  uop
//       // NaN + number = NaN
//       send('h0000_0068, 0, 32'h7FC00000, 32'h3F800000, 5'h1, OP_ADD);
//       // +inf - inf = NaN
//       send('h0000_006C, 1, 32'h7F800000, 32'hFF800000, 5'h2, OP_ADD);

//     end

//     begin
//       recv('h0000_0068, 0, 5'h1, 32'h7FC00000, 1);
//       recv('h0000_006C, 1, 5'h2, 32'h7FC00000, 1);
//     end
//   join

//   t.test_case_end();

//   t.test_case_begin("t_fp_inf");
//   if(!t.run_test) return;

//   fork
//     begin
     
//       //   pc        seq_num  op1(hex)       op2(hex)  waddr  uop
//       // inf + inf = inf
//       send('h0000_0070, 0, 32'h7F800000, 32'h7F800000, 5'h1, OP_ADD);

//       // −inf − inf = −inf
//       send('h0000_0074, 1, 32'hFF800000, 32'hFF800000, 5'h2, OP_ADD);
//     end

//     begin    
//       recv('h0000_0070, 0, 5'h1, 32'h7F800000, 1);
//       recv('h0000_0074, 1, 5'h2, 32'hFF800000, 1);
//     end
//   join

//   t.test_case_end();
// endtask

//----------------------------------------------------------------------
// run_fp_test_cases
//----------------------------------------------------------------------

task run_fp_test_cases();
  test_case_fp_basic();
  // test_case_fp_subnorma();
  // test_case_fp_normal();
  // test_case_fp_extremes();
endtask

