//========================================================================
// illegal_test_cases.v
//========================================================================
// Trap steps use a test-only DPI bridge: FLTrace::vrep rejects traps and
// fl_trace() returns failure even after a successful ISS trap entry.
// The legacy RTL trace checks PC and GPR writeback only. Handler reads
// expose mepc, mcause and mstatus; they do not directly observe CSR updates
// or an RTL trap-valid signal. Direct checks need CSR/trap fields on the
// RTL trace and corresponding ISS DPI fields. No stores, interrupts or
// rename recovery are exercised.

//------------------------------------------------------------------------
// test_case_directed_illegal_1_unknown
//------------------------------------------------------------------------
// Inject an explicitly initialized unrecognized word, not an uninitialized
// fetch or an assembler error. The handler must report cause=2 and mepc=8.
// Known gap: the current ISS throws in FLInst::name() for this word, and
// DIU L6 has no invalid-decode trap path. Keep this a failing test, not an
// end-of-program sentinel or an expected failure. RTL hangs hit the existing
// harness timeout. No substitute instruction or emulated trap is used.

task test_case_directed_illegal_1_unknown();
  h.t.test_case_begin( "test_case_directed_illegal_1_unknown" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, 0x100" );
  h.asm( 'h004, "csrrw x0, 0x305, x1" );
  h.data( 'h008, 32'hffffffff ); // Unrecognized opcode
  h.asm( 'h00c, "addi x2, x0, 0x55" );
  h.asm( 'h010, "jal x0, 0x010" );
  h.asm( 'h100, "csrrs x10, 0x341, x0" );
  h.asm( 'h104, "csrrs x11, 0x342, x0" );
  h.asm( 'h108, "addi x12, x0, 0x2a" );
  h.asm( 'h10c, "jal x0, 0x10c" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'h0000_0100, 1 ); // addi x1, x0, 0x100
  h.check_trace( 'h004, 'x, 'x,          0 ); // csrrw x0, 0x305, x1
  check_trap( 'h008, 2 ); // 4294967295
  h.check_trace( 'h100, 10, 'h0000_0008, 1 ); // csrrs x10, 0x341, x0
  h.check_trace( 'h104, 11, 'h0000_0002, 1 ); // csrrs x11, 0x342, x0
  h.check_trace( 'h108, 12, 'h0000_002a, 1 ); // addi x12, x0, 0x2a

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// run_directed_illegal_tests
//------------------------------------------------------------------------

task run_directed_illegal_tests();
  test_case_directed_illegal_1_unknown();
endtask
