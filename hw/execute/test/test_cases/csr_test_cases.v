//========================================================================
// csr_test_cases.v
//========================================================================
// Author: Emily Lan
//========================================================================

`ifndef CSR_TEST_CASES_V
`define CSR_TEST_CASES_V

//----------------------------------------------------------------------
// test_case_csrrw_basic
//----------------------------------------------------------------------
// CSRRW (atomic read/write): 
//   rd <= old CSR value
//   CSR <= rs1

task test_case_csrrw_basic();
  t.test_case_begin( "test_case_csrrw_basic" );
  if( !t.run_test ) return;

  fork
    begin
      //   pc  seq_num op1 op2 waddr uop
      send('0, 0, 32'h0000_0011, 32'h001, 5'h1, OP_CSRRW);
      send('0, 1, 32'h0000_0022, 32'h001, 5'h2, OP_CSRRW);
    end

    begin
      // recv( pc, seq_num, waddr, wdata, wen )
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  
      recv('0, 1, 5'h2, 32'h0000_0011, 1);  

    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csrrw_frm
//----------------------------------------------------------------------

task test_case_csrrw_frm();
  t.test_case_begin( "test_case_csrrw_frm" );
  if( !t.run_test ) return;

  fork
    begin
      send('0, 0, 32'h0000_0005, 32'h002, 5'h1, OP_CSRRW);
      send('0, 1, 32'h0000_0003, 32'h002, 5'h2, OP_CSRRW);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  
      recv('0, 1, 5'h2, 32'h0000_0005, 1); 
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csrrw_fcsr
//----------------------------------------------------------------------

task test_case_csrrw_fcsr();
  t.test_case_begin( "test_case_csrrw_fcsr" );
  if( !t.run_test ) return;

  fork
    begin
      send('0, 0, 32'h0000_00A5, 32'h003, 5'h1, OP_CSRRW);
      send('0, 1, 32'h0000_0073, 32'h003, 5'h2, OP_CSRRW);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  
      recv('0, 1, 5'h2, 32'h0000_00A5, 1);  
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csrrs_basic
//----------------------------------------------------------------------
// CSRRS (atomic read/set bits): 
//   rd <= old CSR value
//   CSR <= old | rs1

task test_case_csrrs_basic();
  t.test_case_begin( "test_case_csrrs_basic" );
  if( !t.run_test ) return;

  fork
    begin
      send('0, 0, 32'h0000_0003, 32'h001, 5'h1, OP_CSRRW);
      send('0, 1, 32'h0000_0014, 32'h001, 5'h2, OP_CSRRS);
      send('0, 2, 32'h0000_0000, 32'h001, 5'h3, OP_CSRRS);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  
      recv('0, 1, 5'h2, 32'h0000_0003, 1);  
      recv('0, 2, 5'h3, 32'h0000_0017, 1);  
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csrrc_basic
//----------------------------------------------------------------------
// CSRRC (atomic read/clear bits):
//   rd <= old CSR value
//   CSR <= old & ~rs1

task test_case_csrrc_basic();
  t.test_case_begin( "test_case_csrrc_basic" );
  if( !t.run_test ) return;

  fork
    begin
      send('0, 0, 32'h0000_001F, 32'h001, 5'h1, OP_CSRRW);
      send('0, 1, 32'h0000_000C, 32'h001, 5'h2, OP_CSRRC);
      send('0, 2, 32'h0000_0000, 32'h001, 5'h3, OP_CSRRC);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  
      recv('0, 1, 5'h2, 32'h0000_001F, 1);  
      recv('0, 2, 5'h3, 32'h0000_0013, 1); 
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csr_mixed
//----------------------------------------------------------------------

task test_case_csr_mixed();
  t.test_case_begin( "test_case_csr_mixed" );
  if( !t.run_test ) return;

  fork
    begin
      send('0, 0, 32'h0000_0055, 32'h003, 5'h1, OP_CSRRW);
      send('0, 1, 32'h0000_000A, 32'h003, 5'h2, OP_CSRRS);
      send('0, 2, 32'h0000_000C, 32'h003, 5'h3, OP_CSRRC);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);
      recv('0, 1, 5'h2, 32'h0000_0055, 1);
      recv('0, 2, 5'h3, 32'h0000_005F, 1);
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csrrw_rd_x0
//----------------------------------------------------------------------
// When rd = x0, wen should be 0 but the CSR must still be updated.

task test_case_csrrw_rd_x0();
  t.test_case_begin( "test_case_csrrw_rd_x0" );
  if( !t.run_test ) return;

  fork
    begin
      // Write 0x11 to fflags with rd=x0 (write-only)
      send('0, 0, 32'h0000_0011, 32'h001, 5'h0, OP_CSRRW);
      // Read back via CSRRS with rs1=0 (read-only)
      send('0, 1, 32'h0000_0000, 32'h001, 5'h1, OP_CSRRS);
    end

    begin
      recv('0, 0, 5'h0, 32'h0000_0000, 0);  // wen=0 because rd=x0
      recv('0, 1, 5'h1, 32'h0000_0011, 1);  // CSR was updated to 0x11
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csr_truncation
//----------------------------------------------------------------------
// Writing 0xFFFF_FFFF should be truncated to field widths:
//   fflags (5b) -> 0x1F, frm (3b) -> 0x07, fcsr (8b) -> 0xFF

task test_case_csr_truncation();
  t.test_case_begin( "test_case_csr_truncation" );
  if( !t.run_test ) return;

  fork
    begin
      // Write all-ones to fflags, read back truncated
      send('0, 0, 32'hFFFF_FFFF, 32'h001, 5'h1, OP_CSRRW);
      send('0, 1, 32'h0000_0000, 32'h001, 5'h2, OP_CSRRW);
      // Write all-ones to frm, read back truncated
      send('0, 2, 32'hFFFF_FFFF, 32'h002, 5'h3, OP_CSRRW);
      send('0, 3, 32'h0000_0000, 32'h002, 5'h4, OP_CSRRW);
      // Write all-ones to fcsr, read back truncated
      send('0, 4, 32'hFFFF_FFFF, 32'h003, 5'h5, OP_CSRRW);
      send('0, 5, 32'h0000_0000, 32'h003, 5'h6, OP_CSRRW);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  // old fflags = 0
      recv('0, 1, 5'h2, 32'h0000_001F, 1);  // truncated to 5 bits
      recv('0, 2, 5'h3, 32'h0000_0000, 1);  // old frm = 0
      recv('0, 3, 5'h4, 32'h0000_0007, 1);  // truncated to 3 bits
      recv('0, 4, 5'h5, 32'h0000_0000, 1);  // old fcsr = 0
      recv('0, 5, 5'h6, 32'h0000_00FF, 1);  // truncated to 8 bits
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csr_cross_coherence
//----------------------------------------------------------------------
// Writing fflags/frm individually and reading fcsr (and vice versa)
// to verify the composite register stays coherent.

task test_case_csr_cross_coherence();
  t.test_case_begin( "test_case_csr_cross_coherence" );
  if( !t.run_test ) return;

  fork
    begin
      // Write fflags=0x1F via addr 0x001
      send('0, 0, 32'h0000_001F, 32'h001, 5'h1, OP_CSRRW);
      // Write frm=0x7 via addr 0x002
      send('0, 1, 32'h0000_0007, 32'h002, 5'h2, OP_CSRRW);
      // Read fcsr via addr 0x003 (should be {frm, fflags} = 0xFF)
      send('0, 2, 32'h0000_0000, 32'h003, 5'h3, OP_CSRRS);
      // Now write fcsr=0xA5 via addr 0x003
      send('0, 3, 32'h0000_00A5, 32'h003, 5'h4, OP_CSRRW);
      // Read fflags via addr 0x001 (should be 0x05)
      send('0, 4, 32'h0000_0000, 32'h001, 5'h5, OP_CSRRS);
      // Read frm via addr 0x002 (should be 0x05)
      send('0, 5, 32'h0000_0000, 32'h002, 5'h6, OP_CSRRS);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  // old fflags = 0
      recv('0, 1, 5'h2, 32'h0000_0000, 1);  // old frm = 0
      recv('0, 2, 5'h3, 32'h0000_00FF, 1);  // fcsr = {0x7, 0x1F} = 0xFF
      recv('0, 3, 5'h4, 32'h0000_00FF, 1);  // old fcsr = 0xFF
      recv('0, 4, 5'h5, 32'h0000_0005, 1);  // fflags = 0xA5[4:0] = 0x05
      recv('0, 5, 5'h6, 32'h0000_0005, 1);  // frm = 0xA5[7:5] = 0x5
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csr_invalid_addr
//----------------------------------------------------------------------
// Accessing an unmapped CSR address should read 0 and writes
// should be silently ignored.

task test_case_csr_invalid_addr();
  t.test_case_begin( "test_case_csr_invalid_addr" );
  if( !t.run_test ) return;

  fork
    begin
      // Write to unknown address
      send('0, 0, 32'hDEAD_BEEF, 32'hFFF, 5'h1, OP_CSRRW);
      // Read back — should still be 0
      send('0, 1, 32'h0000_0000, 32'hFFF, 5'h2, OP_CSRRS);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  // default read = 0
      recv('0, 1, 5'h2, 32'h0000_0000, 1);  // write was ignored
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csr_invalid_addr_set_clear
//----------------------------------------------------------------------
// CSRRS/CSRRC on unmapped CSR addresses should be ignored and must not
// perturb any mapped CSR state.

task test_case_csr_invalid_addr_set_clear();
  t.test_case_begin( "test_case_csr_invalid_addr_set_clear" );
  if( !t.run_test ) return;

  fork
    begin
      // Seed a mapped CSR.
      send('0, 0, 32'h0000_001A, 32'h001, 5'h1, OP_CSRRW);
      // Set/clear against invalid address must be ignored.
      send('0, 1, 32'hFFFF_FFFF, 32'hFFF, 5'h2, OP_CSRRS);
      send('0, 2, 32'hFFFF_FFFF, 32'hFFF, 5'h3, OP_CSRRC);
      // Read mapped CSR back and ensure it is unchanged.
      send('0, 3, 32'h0000_0000, 32'h001, 5'h4, OP_CSRRS);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);
      recv('0, 1, 5'h2, 32'h0000_0000, 1);
      recv('0, 2, 5'h3, 32'h0000_0000, 1);
      recv('0, 3, 5'h4, 32'h0000_001A, 1);
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csrrs_csrrc_frm
//----------------------------------------------------------------------
// CSRRS and CSRRC targeting frm (addr 0x002) specifically.

task test_case_csrrs_csrrc_frm();
  t.test_case_begin( "test_case_csrrs_csrrc_frm" );
  if( !t.run_test ) return;

  fork
    begin
      // Seed frm = 0x3
      send('0, 0, 32'h0000_0003, 32'h002, 5'h1, OP_CSRRW);
      // Set bits: frm = 0x3 | 0x4 = 0x7
      send('0, 1, 32'h0000_0004, 32'h002, 5'h2, OP_CSRRS);
      // Clear bits: frm = 0x7 & ~0x2 = 0x5
      send('0, 2, 32'h0000_0002, 32'h002, 5'h3, OP_CSRRC);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  // old frm = 0
      recv('0, 1, 5'h2, 32'h0000_0003, 1);  // old frm = 0x3
      recv('0, 2, 5'h3, 32'h0000_0007, 1);  // old frm = 0x7
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csrrc_full_clear
//----------------------------------------------------------------------
// CSRRC should be able to clear all bits to zero.

task test_case_csrrc_full_clear();
  t.test_case_begin( "test_case_csrrc_full_clear" );
  if( !t.run_test ) return;

  fork
    begin
      // Seed fflags = 0x1F (all bits set)
      send('0, 0, 32'h0000_001F, 32'h001, 5'h1, OP_CSRRW);
      // Clear all bits: fflags = 0x1F & ~0x1F = 0x0
      send('0, 1, 32'h0000_001F, 32'h001, 5'h2, OP_CSRRC);
      // Read back via CSRRS with rs1=0
      send('0, 2, 32'h0000_0000, 32'h001, 5'h3, OP_CSRRS);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  // old fflags = 0
      recv('0, 1, 5'h2, 32'h0000_001F, 1);  // old fflags = 0x1F
      recv('0, 2, 5'h3, 32'h0000_0000, 1);  // fflags now 0
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csr_rd_x0_set_clear
//----------------------------------------------------------------------
// rd=x0 suppresses register writeback, but CSRRS/CSRRC must still update
// CSR state atomically.

task test_case_csr_rd_x0_set_clear();
  t.test_case_begin( "test_case_csr_rd_x0_set_clear" );
  if( !t.run_test ) return;

  fork
    begin
      // Seed fcsr.
      send('0, 0, 32'h0000_0055, 32'h003, 5'h1, OP_CSRRW);
      // rd=x0 set then clear on fcsr.
      send('0, 1, 32'h0000_000A, 32'h003, 5'h0, OP_CSRRS);
      send('0, 2, 32'h0000_000C, 32'h003, 5'h0, OP_CSRRC);
      // Read final state.
      send('0, 3, 32'h0000_0000, 32'h003, 5'h2, OP_CSRRS);
    end

    begin
      recv('0, 0, 5'h1, 32'h0000_0000, 1);  // old fcsr = 0
      recv('0, 1, 5'h0, 32'h0000_0055, 0);  // old fcsr, rd=x0 => no writeback
      recv('0, 2, 5'h0, 32'h0000_005F, 0);  // old fcsr after set
      recv('0, 3, 5'h2, 32'h0000_0053, 1);  // final fcsr after clear
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// Helpers for CSR tests
//----------------------------------------------------------------------

function automatic logic [31:0] csr_model_read(
  input logic [11:0] addr,
  input logic  [4:0] exp_fflags,
  input logic  [2:0] exp_frm
);
  begin
    unique case (addr)
      12'h001: csr_model_read = {27'b0, exp_fflags};
      12'h002: csr_model_read = {29'b0, exp_frm};
      12'h003: csr_model_read = {24'b0, exp_frm, exp_fflags};
      default: csr_model_read = 32'h0;
    endcase
  end
endfunction

task automatic csr_model_apply(
  inout logic  [4:0] exp_fflags,
  inout logic  [2:0] exp_frm,
  input rv_uop       uop,
  input logic [11:0] addr,
  input logic [31:0] op1
);
  begin
    unique case (uop)
      OP_CSRRW: begin
        case (addr)
          12'h001: exp_fflags = op1[4:0];
          12'h002: exp_frm    = op1[2:0];
          12'h003: begin
            exp_fflags = op1[4:0];
            exp_frm    = op1[7:5];
          end
          default: ;
        endcase
      end
      OP_CSRRS: begin
        case (addr)
          12'h001: exp_fflags = exp_fflags | op1[4:0];
          12'h002: exp_frm    = exp_frm    | op1[2:0];
          12'h003: begin
            exp_fflags = exp_fflags | op1[4:0];
            exp_frm    = exp_frm    | op1[7:5];
          end
          default: ;
        endcase
      end
      OP_CSRRC: begin
        case (addr)
          12'h001: exp_fflags = exp_fflags & ~op1[4:0];
          12'h002: exp_frm    = exp_frm    & ~op1[2:0];
          12'h003: begin
            exp_fflags = exp_fflags & ~op1[4:0];
            exp_frm    = exp_frm    & ~op1[7:5];
          end
          default: ;
        endcase
      end
      default: ;
    endcase
  end
endtask

//----------------------------------------------------------------------
// test_case_csr_randomized_mixed
//----------------------------------------------------------------------

task automatic test_case_csr_randomized_mixed();
  localparam int CNumIters = 160;

  logic               [31:0] rand_pc      [CNumIters];
  logic [p_seq_num_bits-1:0] rand_seq_num [CNumIters];
  logic               [31:0] rand_op1     [CNumIters];
  logic               [11:0] rand_addr    [CNumIters];
  logic                [4:0] rand_waddr   [CNumIters];
  rv_uop                     rand_uop     [CNumIters];

  logic               [31:0] exp_wdata    [CNumIters];
  logic                      exp_wen      [CNumIters];

  logic [4:0] exp_fflags;
  logic [2:0] exp_frm;
  logic [3:0] addr_sel;
  logic [2:0] op1_sel;

  t.test_case_begin( "test_case_csr_randomized_mixed" );
  if( !t.run_test ) return;

  exp_fflags = '0;
  exp_frm    = '0;

  for( int i = 0; i < CNumIters; i++ ) begin
    rand_pc[i]      = 32'($urandom());
    rand_seq_num[i] = p_seq_num_bits'($urandom());
    if ( i < 9 ) begin
      // Deterministic prefix guarantees all cmd x mapped-addr combos hit.
      rand_uop[i] = (i < 3) ? OP_CSRRW : ( (i < 6) ? OP_CSRRS : OP_CSRRC );
      case (i % 3)
        0: begin
          rand_addr[i] = 12'h001;
          rand_op1[i]  = 32'h0000_001F;
        end
        1: begin
          rand_addr[i] = 12'h002;
          rand_op1[i]  = 32'h0000_0007;
        end
        default: begin
          rand_addr[i] = 12'h003;
          rand_op1[i]  = 32'h0000_00FF;
        end
      endcase
      rand_waddr[i] = 5'(i + 1);
    end
    else begin
      // Periodically force rd=x0 to better stress writeback suppression.
      rand_waddr[i] = ( (i % 8) == 0 ) ? 5'd0 : 5'($urandom());

      case (2'($urandom()))
        2'd0: rand_uop[i] = OP_CSRRW;
        2'd1: rand_uop[i] = OP_CSRRS;
        default: rand_uop[i] = OP_CSRRC;
      endcase

      // Inject corner payloads frequently so masking/set/clear edges are hit.
      op1_sel = 3'($urandom());
      unique case (op1_sel)
        3'd0:    rand_op1[i] = 32'h0000_0000;
        3'd1:    rand_op1[i] = 32'hFFFF_FFFF;
        3'd2:    rand_op1[i] = 32'h0000_001F;
        3'd3:    rand_op1[i] = 32'h0000_0007;
        3'd4:    rand_op1[i] = 32'h0000_00E0;
        default: rand_op1[i] = 32'($urandom());
      endcase

      addr_sel = 4'($urandom());
      unique case (addr_sel)
        4'd0, 4'd1, 4'd2, 4'd3, 4'd4: rand_addr[i] = 12'h001;
        4'd5, 4'd6, 4'd7, 4'd8:       rand_addr[i] = 12'h002;
        4'd9, 4'd10, 4'd11:           rand_addr[i] = 12'h003;
        4'd12:                        rand_addr[i] = 12'h000;
        4'd13:                        rand_addr[i] = 12'h004;
        default:                      rand_addr[i] = 12'hfff;
      endcase
    end

    exp_wdata[i] = csr_model_read(rand_addr[i], exp_fflags, exp_frm);
    exp_wen[i]   = (rand_waddr[i] != 5'd0);
    csr_model_apply(exp_fflags, exp_frm, rand_uop[i], rand_addr[i], rand_op1[i]);
  end

  fork
    begin
      for( int i = 0; i < CNumIters; i++ ) begin
        send(
          rand_pc[i], rand_seq_num[i], rand_op1[i],
          {20'b0, rand_addr[i]}, rand_waddr[i], rand_uop[i]
        );
      end
    end

    begin
      for( int i = 0; i < CNumIters; i++ ) begin
        recv(rand_pc[i], rand_seq_num[i], rand_waddr[i], exp_wdata[i], exp_wen[i]);
      end
    end
  join

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// test_case_csr_randomized_rd_x0
//----------------------------------------------------------------------
// Random write-only CSR operations using rd=x0. Each write is followed by
// a read-back to verify state changed even when writeback is suppressed.

task automatic test_case_csr_randomized_rd_x0();
  localparam int CNumIters = 40;

  logic [4:0] exp_fflags;
  logic [2:0] exp_frm;

  logic               [31:0] op1;
  logic               [31:0] wr_old;
  logic               [31:0] rd_old;
  logic               [11:0] addr;
  logic [p_seq_num_bits-1:0] seq_wr;
  logic [p_seq_num_bits-1:0] seq_rd;
  rv_uop                     wr_uop;
  logic                [2:0] op1_sel;

  t.test_case_begin( "test_case_csr_randomized_rd_x0" );
  if( !t.run_test ) return;

  exp_fflags = '0;
  exp_frm    = '0;

  for( int i = 0; i < CNumIters; i++ ) begin
    // Use corner payloads often so set/clear no-op/full-op behavior is stressed.
    op1_sel = 3'($urandom());
    unique case (op1_sel)
      3'd0:    op1 = 32'h0000_0000;
      3'd1:    op1 = 32'hFFFF_FFFF;
      3'd2:    op1 = 32'h0000_001F;
      3'd3:    op1 = 32'h0000_0007;
      default: op1 = 32'($urandom());
    endcase

    seq_wr = p_seq_num_bits'(2*i);
    seq_rd = p_seq_num_bits'(2*i + 1);

    case (2'($urandom()))
      2'd0: wr_uop = OP_CSRRW;
      2'd1: wr_uop = OP_CSRRS;
      default: wr_uop = OP_CSRRC;
    endcase

    case (3'($urandom()))
      3'd0, 3'd1: addr = 12'h001;
      3'd2, 3'd3: addr = 12'h002;
      3'd4, 3'd5: addr = 12'h003;
      default:    addr = 12'hFFF;
    endcase

    wr_old = csr_model_read(addr, exp_fflags, exp_frm);
    csr_model_apply(exp_fflags, exp_frm, wr_uop, addr, op1);
    rd_old = csr_model_read(addr, exp_fflags, exp_frm);

    fork
      begin
        send('0, seq_wr, op1, {20'b0, addr}, 5'h0, wr_uop);
        send('0, seq_rd, 32'h0, {20'b0, addr}, 5'h1, OP_CSRRS);
      end

      begin
        recv('0, seq_wr, 5'h0, wr_old, 0);
        recv('0, seq_rd, 5'h1, rd_old, 1);
      end
    join
  end

  t.test_case_end();
endtask

//----------------------------------------------------------------------
// run_csr_test_cases
//----------------------------------------------------------------------

task run_csr_test_cases();
  test_case_csrrw_basic();
  test_case_csrrw_frm();
  test_case_csrrw_fcsr();
  test_case_csrrs_basic();
  test_case_csrrc_basic();
  test_case_csr_mixed();
  test_case_csrrw_rd_x0();
  test_case_csr_truncation();
  test_case_csr_cross_coherence();
  test_case_csr_invalid_addr();
  test_case_csr_invalid_addr_set_clear();
  test_case_csrrs_csrrc_frm();
  test_case_csrrc_full_clear();
  test_case_csr_rd_x0_set_clear();
  test_case_csr_randomized_mixed();
  test_case_csr_randomized_rd_x0();
endtask

`endif
