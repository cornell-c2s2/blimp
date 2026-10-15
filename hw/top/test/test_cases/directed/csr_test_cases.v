//========================================================================
// csr_test_cases.v
//========================================================================
// The same directed cases run on FLProc and BlimpV9_csr. The RTL suite
// also compares each bounded retirement against the ISS golden trace.
// CSR reads expose values through GPR writeback; the trace does not expose
// CSR state at every commit. Direct checking needs CSR address, command,
// write enable and resulting value in the RTL trace and the ISS DPI.
// Do not use check_traces(): an ISS failure must not end a test successfully.

//------------------------------------------------------------------------
// test_case_directed_csr_1_round_trip
//------------------------------------------------------------------------
// Round trip full-width values through mscratch (0x340) and mtval (0x343).
// The second write returns the previous value; reads distinguish the CSRs.

task test_case_directed_csr_1_round_trip();
  h.t.test_case_begin( "test_case_directed_csr_1_round_trip" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, -1" );
  h.asm( 'h004, "lui x2, 0x12345" );
  h.asm( 'h008, "addi x2, x2, 0x678" );
  h.asm( 'h00c, "csrrw x3, 0x340, x1" );
  h.asm( 'h010, "csrrw x4, 0x343, x2" );
  h.asm( 'h014, "csrrs x5, 0x340, x0" );
  h.asm( 'h018, "csrrs x6, 0x343, x0" );
  h.asm( 'h01c, "csrrw x7, 0x340, x2" );
  h.asm( 'h020, "csrrw x8, 0x343, x1" );
  h.asm( 'h024, "csrrs x9, 0x340, x0" );
  h.asm( 'h028, "csrrs x10, 0x343, x0" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'hffff_ffff, 1 ); // addi x1, x0, -1
  h.check_trace( 'h004,  2, 'h1234_5000, 1 ); // lui x2, 0x12345
  h.check_trace( 'h008,  2, 'h1234_5678, 1 ); // addi x2, x2, 0x678
  h.check_trace( 'h00c,  3, 'h0000_0000, 1 ); // csrrw x3, 0x340, x1
  h.check_trace( 'h010,  4, 'h0000_0000, 1 ); // csrrw x4, 0x343, x2
  h.check_trace( 'h014,  5, 'hffff_ffff, 1 ); // csrrs x5, 0x340, x0
  h.check_trace( 'h018,  6, 'h1234_5678, 1 ); // csrrs x6, 0x343, x0
  h.check_trace( 'h01c,  7, 'hffff_ffff, 1 ); // csrrw x7, 0x340, x2
  h.check_trace( 'h020,  8, 'h1234_5678, 1 ); // csrrw x8, 0x343, x1
  h.check_trace( 'h024,  9, 'h1234_5678, 1 ); // csrrs x9, 0x340, x0
  h.check_trace( 'h028, 10, 'hffff_ffff, 1 ); // csrrs x10, 0x343, x0

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// test_case_directed_csr_2_set_clear
//------------------------------------------------------------------------
// Overlapping masks distinguish SET/CLEAR from replacement writes.

task test_case_directed_csr_2_set_clear();
  h.t.test_case_begin( "test_case_directed_csr_2_set_clear" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, 0xf0" );
  h.asm( 'h004, "csrrw x2, 0x340, x1" );
  h.asm( 'h008, "addi x3, x0, 0x3c" );
  h.asm( 'h00c, "csrrs x4, 0x340, x3" );
  h.asm( 'h010, "csrrs x5, 0x340, x0" );
  h.asm( 'h014, "addi x6, x0, 0x5c" );
  h.asm( 'h018, "csrrc x7, 0x340, x6" );
  h.asm( 'h01c, "csrrs x8, 0x340, x0" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'h0000_00f0, 1 ); // addi x1, x0, 0xf0
  h.check_trace( 'h004,  2, 'h0000_0000, 1 ); // csrrw x2, 0x340, x1
  h.check_trace( 'h008,  3, 'h0000_003c, 1 ); // addi x3, x0, 0x3c
  h.check_trace( 'h00c,  4, 'h0000_00f0, 1 ); // csrrs x4, 0x340, x3
  h.check_trace( 'h010,  5, 'h0000_00fc, 1 ); // csrrs x5, 0x340, x0
  h.check_trace( 'h014,  6, 'h0000_005c, 1 ); // addi x6, x0, 0x5c
  h.check_trace( 'h018,  7, 'h0000_00fc, 1 ); // csrrc x7, 0x340, x6
  h.check_trace( 'h01c,  8, 'h0000_00a0, 1 ); // csrrs x8, 0x340, x0

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// test_case_directed_csr_3_immediate
//------------------------------------------------------------------------
// Exercise all immediate forms, the maximum zimm and zero masks.
// Set x21 to a different value to detect an erroneous register operand.

task test_case_directed_csr_3_immediate();
  h.t.test_case_begin( "test_case_directed_csr_3_immediate" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x21, x0, 0x123" );
  h.asm( 'h004, "csrrwi x1, 0x340, 21" );
  h.asm( 'h008, "csrrsi x2, 0x340, 10" );
  h.asm( 'h00c, "csrrci x3, 0x340, 9" );
  h.asm( 'h010, "csrrsi x4, 0x340, 0" );
  h.asm( 'h014, "csrrci x5, 0x340, 0" );
  h.asm( 'h018, "csrrwi x6, 0x340, 31" );
  h.asm( 'h01c, "csrrwi x7, 0x340, 0" );
  h.asm( 'h020, "csrrs x8, 0x340, x0" );

  // Check each executed instruction

  h.check_trace( 'h000, 21, 'h0000_0123, 1 ); // addi x21, x0, 0x123
  h.check_trace( 'h004,  1, 'h0000_0000, 1 ); // csrrwi x1, 0x340, 21
  h.check_trace( 'h008,  2, 'h0000_0015, 1 ); // csrrsi x2, 0x340, 10
  h.check_trace( 'h00c,  3, 'h0000_001f, 1 ); // csrrci x3, 0x340, 9
  h.check_trace( 'h010,  4, 'h0000_0016, 1 ); // csrrsi x4, 0x340, 0
  h.check_trace( 'h014,  5, 'h0000_0016, 1 ); // csrrci x5, 0x340, 0
  h.check_trace( 'h018,  6, 'h0000_0016, 1 ); // csrrwi x6, 0x340, 31
  h.check_trace( 'h01c,  7, 'h0000_001f, 1 ); // csrrwi x7, 0x340, 0
  h.check_trace( 'h020,  8, 'h0000_0000, 1 ); // csrrs x8, 0x340, x0

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// test_case_directed_csr_4_x0
//------------------------------------------------------------------------
// CSRRS/CSRRC with rs1=x0 preserve the value; CSRRW with rs1=x0 writes
// zero. CSRRW rd=x0 still writes the CSR and produces no GPR writeback.
// These checks cannot prove suppression of the CSR read or write access:
// all selected CSRs have side-effect-free reads and zero-mask writes are
// value-preserving. Direct verification needs read/write-enable monitoring
// and source-register identity at the CSR interface (or a side-effect CSR).

task test_case_directed_csr_4_x0();
  h.t.test_case_begin( "test_case_directed_csr_4_x0" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, 0x5a5" );
  h.asm( 'h004, "csrrw x0, 0x340, x1" );
  h.asm( 'h008, "csrrs x2, 0x340, x0" );
  h.asm( 'h00c, "csrrc x3, 0x340, x0" );
  h.asm( 'h010, "csrrs x4, 0x340, x0" );
  h.asm( 'h014, "addi x5, x0, 7" );
  h.asm( 'h018, "csrrw x6, 0x340, x0" );
  h.asm( 'h01c, "csrrs x7, 0x340, x0" );
  h.asm( 'h020, "csrrwi x0, 0x340, 19" );
  h.asm( 'h024, "csrrs x8, 0x340, x0" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'h0000_05a5, 1 ); // addi x1, x0, 0x5a5
  h.check_trace( 'h004, 'x, 'x,          0 ); // csrrw x0, 0x340, x1
  h.check_trace( 'h008,  2, 'h0000_05a5, 1 ); // csrrs x2, 0x340, x0
  h.check_trace( 'h00c,  3, 'h0000_05a5, 1 ); // csrrc x3, 0x340, x0
  h.check_trace( 'h010,  4, 'h0000_05a5, 1 ); // csrrs x4, 0x340, x0
  h.check_trace( 'h014,  5, 'h0000_0007, 1 ); // addi x5, x0, 7
  h.check_trace( 'h018,  6, 'h0000_05a5, 1 ); // csrrw x6, 0x340, x0
  h.check_trace( 'h01c,  7, 'h0000_0000, 1 ); // csrrs x7, 0x340, x0
  h.check_trace( 'h020, 'x, 'x,          0 ); // csrrwi x0, 0x340, 19
  h.check_trace( 'h024,  8, 'h0000_0013, 1 ); // csrrs x8, 0x340, x0

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// test_case_directed_csr_5_alignment
//------------------------------------------------------------------------
// mtvec and mepc discard the low two bits.

task test_case_directed_csr_5_alignment();
  h.t.test_case_begin( "test_case_directed_csr_5_alignment" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, 0x103" );
  h.asm( 'h004, "csrrw x2, 0x305, x1" );
  h.asm( 'h008, "csrrs x3, 0x305, x0" );
  h.asm( 'h00c, "addi x4, x0, 0x207" );
  h.asm( 'h010, "csrrw x5, 0x341, x4" );
  h.asm( 'h014, "csrrs x6, 0x341, x0" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'h0000_0103, 1 ); // addi x1, x0, 0x103
  h.check_trace( 'h004,  2, 'h0000_0000, 1 ); // csrrw x2, 0x305, x1
  h.check_trace( 'h008,  3, 'h0000_0100, 1 ); // csrrs x3, 0x305, x0
  h.check_trace( 'h00c,  4, 'h0000_0207, 1 ); // addi x4, x0, 0x207
  h.check_trace( 'h010,  5, 'h0000_0000, 1 ); // csrrw x5, 0x341, x4
  h.check_trace( 'h014,  6, 'h0000_0204, 1 ); // csrrs x6, 0x341, x0

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// test_case_directed_csr_6_masks
//------------------------------------------------------------------------
// mstatus permits MIE/MPIE and fixes MPP=11; mie permits only MTIE.
// mip remains zero after a write. This does not inject timer interrupts.
//
// Expected RTL failure: hw/csr/CSRFile.v does not implement mie (0x304)
// yet; timer interrupts are out of scope for this change. The RTL reads
// 0x304 as zero, so the x7 readback (expected 0x80) fails on BlimpV9_csr.
// The ISS implements mie, so FLProc passes. Keep this check as the target
// behavior for when mie is added.

task test_case_directed_csr_6_masks();
  h.t.test_case_begin( "test_case_directed_csr_6_masks" );
  if( !h.t.run_test ) return;
  fl_reset();

  // Write assembly program into memory

  h.asm( 'h000, "addi x1, x0, -1" );
  h.asm( 'h004, "csrrw x2, 0x300, x1" );
  h.asm( 'h008, "csrrs x3, 0x300, x0" );
  h.asm( 'h00c, "csrrw x4, 0x300, x0" );
  h.asm( 'h010, "csrrs x5, 0x300, x0" );
  h.asm( 'h014, "csrrw x6, 0x304, x1" );
  h.asm( 'h018, "csrrs x7, 0x304, x0" );
  h.asm( 'h01c, "csrrw x8, 0x344, x1" );
  h.asm( 'h020, "csrrs x9, 0x344, x0" );

  // Check each executed instruction

  h.check_trace( 'h000,  1, 'hffff_ffff, 1 ); // addi x1, x0, -1
  h.check_trace( 'h004,  2, 'h0000_1800, 1 ); // csrrw x2, 0x300, x1
  h.check_trace( 'h008,  3, 'h0000_1888, 1 ); // csrrs x3, 0x300, x0
  h.check_trace( 'h00c,  4, 'h0000_1888, 1 ); // csrrw x4, 0x300, x0
  h.check_trace( 'h010,  5, 'h0000_1800, 1 ); // csrrs x5, 0x300, x0
  h.check_trace( 'h014,  6, 'h0000_0000, 1 ); // csrrw x6, 0x304, x1
  h.check_trace( 'h018,  7, 'h0000_0080, 1 ); // csrrs x7, 0x304, x0
  h.check_trace( 'h01c,  8, 'h0000_0000, 1 ); // csrrw x8, 0x344, x1
  h.check_trace( 'h020,  9, 'h0000_0000, 1 ); // csrrs x9, 0x344, x0

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// run_directed_csr_tests
//------------------------------------------------------------------------

task run_directed_csr_tests();
  test_case_directed_csr_1_round_trip();
  test_case_directed_csr_2_set_clear();
  test_case_directed_csr_3_immediate();
  test_case_directed_csr_4_x0();
  test_case_directed_csr_5_alignment();
  test_case_directed_csr_6_masks();
endtask
