//========================================================================
// trap_test_cases.v
//========================================================================
// Trap steps use a test-only DPI bridge: FLTrace::vrep rejects traps and
// fl_trace() returns failure even after a successful ISS trap entry.
// The legacy RTL trace checks PC and GPR writeback only. Handler reads
// expose mepc, mcause and mstatus; they do not directly observe CSR updates
// or an RTL trap-valid signal. Direct checks need CSR/trap fields on the
// RTL trace and corresponding ISS DPI fields. No stores, interrupts or
// rename recovery are exercised.

//------------------------------------------------------------------------
// test_case_directed_trap_1_ecall
//------------------------------------------------------------------------
// The multiply must drain before the trap. Handler PCs and the dependent
// marker verify redirect and preserved older results; fall-through must not
// retire. The bounded check stops at the marker, before the terminal loop.

task test_case_directed_trap_1_ecall();
  h.t.test_case_begin( "test_case_directed_trap_1_ecall" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, 0x100" );
  h.asm( 'h004, "csrrw x0, 0x305, x1" );
  h.asm( 'h008, "addi x2, x0, 7" );
  h.asm( 'h00c, "mul x3, x2, x2" );
  h.asm( 'h010, "ecall" );
  h.asm( 'h014, "addi x4, x0, 0x55" );
  h.asm( 'h018, "jal x0, 0x018" );
  h.asm( 'h100, "csrrs x10, 0x341, x0" );
  h.asm( 'h104, "csrrs x11, 0x342, x0" );
  h.asm( 'h108, "addi x12, x3, 1" );
  h.asm( 'h10c, "jal x0, 0x10c" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'h0000_0100, 1 ); // addi x1, x0, 0x100
  h.check_trace( 'h004, 'x, 'x,          0 ); // csrrw x0, 0x305, x1
  h.check_trace( 'h008,  2, 'h0000_0007, 1 ); // addi x2, x0, 7
  h.check_trace( 'h00c,  3, 'h0000_0031, 1 ); // mul x3, x2, x2
  check_trap( 'h010, 11 ); // ecall
  h.check_trace( 'h100, 10, 'h0000_0010, 1 ); // csrrs x10, 0x341, x0
  h.check_trace( 'h104, 11, 'h0000_000b, 1 ); // csrrs x11, 0x342, x0
  h.check_trace( 'h108, 12, 'h0000_0032, 1 ); // addi x12, x3, 1

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// test_case_directed_trap_2_ebreak
//------------------------------------------------------------------------
// The multiply must drain before the trap. Handler PCs and the dependent
// marker verify redirect and preserved older results; fall-through must not
// retire. The bounded check stops at the marker, before the terminal loop.

task test_case_directed_trap_2_ebreak();
  h.t.test_case_begin( "test_case_directed_trap_2_ebreak" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, 0x100" );
  h.asm( 'h004, "csrrw x0, 0x305, x1" );
  h.asm( 'h008, "addi x2, x0, 7" );
  h.asm( 'h00c, "mul x3, x2, x2" );
  h.asm( 'h010, "ebreak" );
  h.asm( 'h014, "addi x4, x0, 0x55" );
  h.asm( 'h018, "jal x0, 0x018" );
  h.asm( 'h100, "csrrs x10, 0x341, x0" );
  h.asm( 'h104, "csrrs x11, 0x342, x0" );
  h.asm( 'h108, "addi x12, x3, 1" );
  h.asm( 'h10c, "jal x0, 0x10c" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'h0000_0100, 1 ); // addi x1, x0, 0x100
  h.check_trace( 'h004, 'x, 'x,          0 ); // csrrw x0, 0x305, x1
  h.check_trace( 'h008,  2, 'h0000_0007, 1 ); // addi x2, x0, 7
  h.check_trace( 'h00c,  3, 'h0000_0031, 1 ); // mul x3, x2, x2
  check_trap( 'h010, 3 ); // ebreak
  h.check_trace( 'h100, 10, 'h0000_0010, 1 ); // csrrs x10, 0x341, x0
  h.check_trace( 'h104, 11, 'h0000_0003, 1 ); // csrrs x11, 0x342, x0
  h.check_trace( 'h108, 12, 'h0000_0032, 1 ); // addi x12, x3, 1

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// test_case_directed_trap_3_mret
//------------------------------------------------------------------------
// Trap entry overwrites MPIE with MIE and clears MIE. The handler advances
// mepc by four before MRET; the next retirement must be PC 0x014, not the
// trap PC or the handler fall-through. MRET restores MIE and sets MPIE.
// Opposite initial MIE/MPIE values detect retaining the old MPIE by mistake.

task test_case_directed_trap_3_mret();
  h.t.test_case_begin( "test_case_directed_trap_3_mret" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, 0x100" );
  h.asm( 'h004, "csrrw x0, 0x305, x1" );
  h.asm( 'h008, "addi x2, x0, 0x8" );
  h.asm( 'h00c, "csrrw x0, 0x300, x2" );
  h.asm( 'h010, "ecall" );
  h.asm( 'h014, "csrrs x13, 0x300, x0" );
  h.asm( 'h018, "addi x14, x12, 1" );
  h.asm( 'h01c, "jal x0, 0x01c" );
  h.asm( 'h100, "csrrs x10, 0x341, x0" );
  h.asm( 'h104, "csrrs x11, 0x342, x0" );
  h.asm( 'h108, "csrrs x12, 0x300, x0" );
  h.asm( 'h10c, "addi x10, x10, 4" );
  h.asm( 'h110, "csrrw x0, 0x341, x10" );
  h.asm( 'h114, "mret" );
  h.asm( 'h118, "addi x15, x0, 0x66" );
  h.asm( 'h11c, "jal x0, 0x11c" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'h0000_0100, 1 ); // addi x1, x0, 0x100
  h.check_trace( 'h004, 'x, 'x,          0 ); // csrrw x0, 0x305, x1
  h.check_trace( 'h008,  2, 'h0000_0008, 1 ); // addi x2, x0, 0x8
  h.check_trace( 'h00c, 'x, 'x,          0 ); // csrrw x0, 0x300, x2
  check_trap( 'h010, 11 ); // ecall
  h.check_trace( 'h100, 10, 'h0000_0010, 1 ); // csrrs x10, 0x341, x0
  h.check_trace( 'h104, 11, 'h0000_000b, 1 ); // csrrs x11, 0x342, x0
  h.check_trace( 'h108, 12, 'h0000_1880, 1 ); // csrrs x12, 0x300, x0
  h.check_trace( 'h10c, 10, 'h0000_0014, 1 ); // addi x10, x10, 4
  h.check_trace( 'h110, 'x, 'x,          0 ); // csrrw x0, 0x341, x10
  h.check_trace( 'h114, 'x, 'x,          0 ); // mret
  h.check_trace( 'h014, 13, 'h0000_1888, 1 ); // csrrs x13, 0x300, x0
  h.check_trace( 'h018, 14, 'h0000_1881, 1 ); // addi x14, x12, 1

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// test_case_directed_trap_4_mie_disabled
//------------------------------------------------------------------------
// Trap entry overwrites MPIE with MIE and clears MIE. The handler advances
// mepc by four before MRET; the next retirement must be PC 0x014, not the
// trap PC or the handler fall-through. MRET restores MIE and sets MPIE.
// Opposite initial MIE/MPIE values detect retaining the old MPIE by mistake.

task test_case_directed_trap_4_mie_disabled();
  h.t.test_case_begin( "test_case_directed_trap_4_mie_disabled" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, 0x100" );
  h.asm( 'h004, "csrrw x0, 0x305, x1" );
  h.asm( 'h008, "addi x2, x0, 0x80" );
  h.asm( 'h00c, "csrrw x0, 0x300, x2" );
  h.asm( 'h010, "ecall" );
  h.asm( 'h014, "csrrs x13, 0x300, x0" );
  h.asm( 'h018, "addi x14, x12, 1" );
  h.asm( 'h01c, "jal x0, 0x01c" );
  h.asm( 'h100, "csrrs x10, 0x341, x0" );
  h.asm( 'h104, "csrrs x11, 0x342, x0" );
  h.asm( 'h108, "csrrs x12, 0x300, x0" );
  h.asm( 'h10c, "addi x10, x10, 4" );
  h.asm( 'h110, "csrrw x0, 0x341, x10" );
  h.asm( 'h114, "mret" );
  h.asm( 'h118, "addi x15, x0, 0x66" );
  h.asm( 'h11c, "jal x0, 0x11c" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'h0000_0100, 1 ); // addi x1, x0, 0x100
  h.check_trace( 'h004, 'x, 'x,          0 ); // csrrw x0, 0x305, x1
  h.check_trace( 'h008,  2, 'h0000_0080, 1 ); // addi x2, x0, 0x80
  h.check_trace( 'h00c, 'x, 'x,          0 ); // csrrw x0, 0x300, x2
  check_trap( 'h010, 11 ); // ecall
  h.check_trace( 'h100, 10, 'h0000_0010, 1 ); // csrrs x10, 0x341, x0
  h.check_trace( 'h104, 11, 'h0000_000b, 1 ); // csrrs x11, 0x342, x0
  h.check_trace( 'h108, 12, 'h0000_1800, 1 ); // csrrs x12, 0x300, x0
  h.check_trace( 'h10c, 10, 'h0000_0014, 1 ); // addi x10, x10, 4
  h.check_trace( 'h110, 'x, 'x,          0 ); // csrrw x0, 0x341, x10
  h.check_trace( 'h114, 'x, 'x,          0 ); // mret
  h.check_trace( 'h014, 13, 'h0000_1880, 1 ); // csrrs x13, 0x300, x0
  h.check_trace( 'h018, 14, 'h0000_1801, 1 ); // addi x14, x12, 1

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// run_directed_trap_tests
//------------------------------------------------------------------------

task run_directed_trap_tests();
  test_case_directed_trap_1_ecall();
  test_case_directed_trap_2_ebreak();
  test_case_directed_trap_3_mret();
  test_case_directed_trap_4_mie_disabled();
endtask
