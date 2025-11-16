//========================================================================
// lw_test_cases.v
//========================================================================

//------------------------------------------------------------------------
// test_case_randomized_lw_1_offset
//------------------------------------------------------------------------

task test_case_randomized_lw_1_offset();
  integer offset;
  integer addr;
  integer data;
  integer base_addr;
  integer pc;
  string  inst;
  integer unused;

  h.t.test_case_begin( "test_case_randomized_lw_1_offset" );
  if( !h.t.run_test ) return;
  fl_reset();

  unused = $urandom(seed);

  base_addr = 'h2000;

  // Write assembly program and data into memory

  h.asm( 'h200, "addi x1, x0, 0x200" );
  h.asm( 'h204, "slli x1, x1, 4"     );

  pc = 'h208;

  for (int i = 0; i < 200; i++) begin
    
    // Determine address to read from and data to read

    offset = {{ 21{1'($urandom)}}, 9'($urandom), 2'b0};

    addr = base_addr + offset;

    data = 32'($urandom);

    // Write h.data into memory

    h.data( addr, data );

    // Write instruction

    inst = $sformatf("lw x2, %d(x1)", offset);
    h.asm( pc, inst );

    pc = pc + 4;
  end

  // Check each executed instruction
  
  h.check_traces();

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// test_case_randomized_lw_2_chains
//------------------------------------------------------------------------

task test_case_randomized_lw_2_chains();
  integer unused;
  integer pc;
  string  inst;
  integer addr;
  integer data;

  bit select_chain;
  bit select_inst;
  integer reg_fl [9];
  integer rd_idx;
  integer rs1_idx;
  integer rs2_idx;

  integer mem [128];

  integer reg_tr [500];
  integer wdata_tr [500];

  h.t.test_case_begin( "test_case_randomized_lw_2_chains" );
  if( !h.t.run_test ) return;
  fl_reset();

  seed = 32'hC252C252;

  unused = $urandom(seed + 1);

  // Initialize the registers for both chains

  for (int i = 0; i < 8; i++) begin
    reg_fl[i+1] = 32'h100 + (i << 4);
  end

  // Initialize memory randomly

  for (int i = 0; i < 128; i++) begin
    mem[i] = $urandom() & 32'h1fc;
    h.data( i << 2, mem[i] );
  end

  h.asm( 'h200, "addi x1, x0, 0x100" );
  h.asm( 'h204, "addi x2, x0, 0x110" );
  h.asm( 'h208, "addi x3, x0, 0x120" );
  h.asm( 'h20c, "addi x4, x0, 0x130" );
  h.asm( 'h210, "addi x5, x0, 0x140" );
  h.asm( 'h214, "addi x6, x0, 0x150" );
  h.asm( 'h218, "addi x7, x0, 0x160" );
  h.asm( 'h21c, "addi x8, x0, 0x170" );

  pc = 'h220;

  for (int i = 0; i < 500; i++) begin
    select_chain = 1'($urandom());
    select_inst  = 1'($urandom());

    // Determine which chain to write to

    if (select_chain == 0) begin
      rd_idx  = {30'b0, 2'($urandom())} + 1;
      rs1_idx = {30'b0, 2'($urandom())} + 1;
      rs2_idx = {30'b0, 2'($urandom())} + 1;
    end
    else begin
      rd_idx  = {30'b01, 2'($urandom())} + 1;
      rs1_idx = {30'b01, 2'($urandom())} + 1;
      rs2_idx = {30'b01, 2'($urandom())} + 1;
    end

    // Determine which instruction to write

    if (select_inst == 0) begin
      inst = $sformatf("xor x%0d, x%0d, x%0d", rd_idx, rs1_idx, rs2_idx);

      reg_fl[rd_idx] = reg_fl[rs1_idx] ^ reg_fl[rs2_idx];
    end 
    else begin
      addr = reg_fl[rs1_idx];
      data = mem[(addr >> 2)];

      inst = $sformatf("lw x%0d, 0(x%0d)", rd_idx, rs1_idx);

      reg_fl[rd_idx] = data;
    end

    reg_tr[i] = rd_idx;
    wdata_tr[i] = reg_fl[rd_idx];

    h.asm(pc, inst);
    pc = pc + 4;
  end

  // Verify traces
  h.check_traces();

  // h.check_trace( 'h200, 1, 'h0000_0100, 1 );
  // h.check_trace( 'h204, 2, 'h0000_0110, 1 );
  // h.check_trace( 'h208, 3, 'h0000_0120, 1 );
  // h.check_trace( 'h20c, 4, 'h0000_0130, 1 );
  // h.check_trace( 'h210, 5, 'h0000_0140, 1 );
  // h.check_trace( 'h214, 6, 'h0000_0150, 1 );
  // h.check_trace( 'h218, 7, 'h0000_0160, 1 );
  // h.check_trace( 'h21c, 8, 'h0000_0170, 1 );

  // for (int i = 0; i < 500; i++) begin
  //   h.check_trace( 'h220 + i*4, reg_tr[i], wdata_tr[i], 1 );
  // end

  h.t.test_case_end();
endtask

//------------------------------------------------------------------------
// run_randomized_lw_tests
//------------------------------------------------------------------------

task run_randomized_lw_tests();
  test_case_randomized_lw_1_offset();
  test_case_randomized_lw_2_chains();
endtask
