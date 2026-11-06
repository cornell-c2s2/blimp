//========================================================================
// BlimpV10_sim.v
//========================================================================
// A module for simulating BlimpV10

`include "asm/assemble.v"
`include "hw/top/BlimpV10.v"
`include "hw/top/sim/utils/SimUtils.v"
`include "intf/MemIntf.v"
`include "intf/InstTraceNotif.v"
`include "test/fl/MemIntfTestServer_NPort.v"

import "DPI-C" context function void load_elf ( string elf_file );

module BlimpV10_sim;

  // Define default simulation parameters
  localparam p_num_phys_regs = 36;
  localparam p_opaq_bits     = 8;
  localparam p_seq_num_bits  = 5;
  
  //----------------------------------------------------------------------
  // Setup
  //----------------------------------------------------------------------

  logic clk;
  logic rst;

  SimUtils t( .* );

  `MEM_REQ_DEFINE ( p_opaq_bits );
  `MEM_RESP_DEFINE( p_opaq_bits );

  //----------------------------------------------------------------------
  // Instantiate processor
  //----------------------------------------------------------------------

  MemIntf #(
    .p_opaq_bits (p_opaq_bits)
  ) mem_intf[3]();

  InstTraceNotif inst_trace_notif();

  BlimpV10 #(
    .p_opaq_bits     (p_opaq_bits),
    .p_seq_num_bits  (p_seq_num_bits),
    .p_num_phys_regs (p_num_phys_regs)
  ) dut (
    .inst_mem           (mem_intf[0]),
    .data_mem           (mem_intf[1]),
    .store_mem          (mem_intf[2]),
    .inst_trace         (inst_trace_notif),
    .inst_trace_deq_rdy (1'b1),
    .debug              (1'b0),
    .*
  );

  logic [31:0] inst_trace_pc;
  logic  [4:0] inst_trace_waddr;
  logic [31:0] inst_trace_wdata;
  logic        inst_trace_wen;
  logic        inst_trace_val;

  assign inst_trace_pc    = inst_trace_notif.pc;
  assign inst_trace_waddr = inst_trace_notif.waddr;
  assign inst_trace_wdata = inst_trace_notif.wdata;
  assign inst_trace_wen   = inst_trace_notif.wen;
  assign inst_trace_val   = inst_trace_notif.val;

  always @( posedge clk ) begin
    #2;
    if( inst_trace_val ) begin
      t.inst_trace(
        inst_trace_pc,
        inst_trace_waddr,
        inst_trace_wdata,
        inst_trace_wen
      );
    end
  end

  //----------------------------------------------------------------------
  // FL Memory
  //----------------------------------------------------------------------

  MemIntfTestServer_NPort #(
    .t_req_msg         (`MEM_REQ ( p_opaq_bits )),
    .t_resp_msg        (`MEM_RESP( p_opaq_bits )),
    .p_num_ports       ( 3 ),
    .p_send_intv_delay ( 1 ),
    .p_recv_intv_delay ( 1 ),
    .p_opaq_bits       (p_opaq_bits)
  ) fl_mem (
    .dut (mem_intf),
    .*
  );

  function void init_mem(
    input bit [31:0] addr,
    input bit [31:0] data
  );
    fl_mem.init_mem( addr, data );
  endfunction

  export "DPI-C" function init_mem;

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------

  string trace;

  // verilator lint_off BLKSEQ
  always @( posedge clk ) begin
    #2;
    trace = "";

    trace = {trace, fl_mem.trace( t.trace_level )};
    trace = {trace, " || "};
    trace = {trace, dut.trace( t.trace_level )};
    trace = {trace, " || "};

    // Instruction trace
    if( inst_trace_val ) begin
      trace = {trace, $sformatf("0x%08x: ", inst_trace_pc)};
      if( inst_trace_wen ) begin
        trace = {trace, $sformatf("0x%08x -> R[%0d]", inst_trace_wdata, inst_trace_waddr)};
      end
    end

    t.trace( trace );
  end
  // verilator lint_on BLKSEQ

  //----------------------------------------------------------------------
  // Counters
  //----------------------------------------------------------------------
  longint n_cycles, n_commit, n_sq_branch, n_sq_trap,
          n_fetch_empty, n_decode_stall, n_store_block;
  longint n_issue_stall[5], n_wb_stall[5];

  logic stats_en, stats_en_prev;
  assign stats_en = fl_mem.stats_en;

  always @( posedge clk ) if( !rst && stats_en ) begin
    n_cycles++;
    if(  dut.commit_notif.val )                            n_commit++;
    if(  dut.squash_arb_notif[3].val )                     n_sq_branch++;   // branch/jump redirect at commit
    if(  dut.squash_arb_notif[2].val )                     n_sq_trap++;     // ECALL/EBREAK/MRET
    if( !dut.f__d_intf.val )                               n_fetch_empty++; // decode has nothing to work on
    if(  dut.f__d_intf.val & !dut.f__d_intf.rdy )          n_decode_stall++;
    if(  dut.WCU.rob_deq_rdy & dut.WCU.head_is_store
                            & !dut.WCU.csb_push_rdy )     n_store_block++; // commit blocked by store buffer
  end

  for( genvar i = 0; i < 5; i++ ) begin   // 0=ALU 1=MulDiv 2=Mem 3=Ctrl 4=CSR
    always @( posedge clk ) if( !rst && stats_en ) begin
      if( dut.d__x_intfs[i].val & !dut.d__x_intfs[i].rdy ) n_issue_stall[i]++; // unit busy
      if( dut.x__w_intfs[i].val & !dut.x__w_intfs[i].rdy ) n_wb_stall[i]++;    // writeback contention
    end
  end

  // verilator lint_off BLKSEQ
  always @( posedge clk ) begin
    #2;
    if( stats_en_prev & !stats_en ) begin  // kernel just ended
      $display( "[stats] cycles=%0d commits=%0d IPC=%.3f",
                n_cycles, n_commit, real'(n_commit)/n_cycles );
      $display( "[stats] branch_squash=%0d trap_squash=%0d fetch_empty=%0d decode_stall=%0d store_commit_block=%0d",
                n_sq_branch, n_sq_trap, n_fetch_empty, n_decode_stall, n_store_block );
      $display( "[stats] issue_stall  alu=%0d muldiv=%0d mem=%0d ctrl=%0d csr=%0d",
                n_issue_stall[0], n_issue_stall[1], n_issue_stall[2], n_issue_stall[3], n_issue_stall[4] );
      $display( "[stats] wb_stall     alu=%0d muldiv=%0d mem=%0d ctrl=%0d csr=%0d",
                n_wb_stall[0], n_wb_stall[1], n_wb_stall[2], n_wb_stall[3], n_wb_stall[4] );
    end
    stats_en_prev = stats_en;
  end
  // verilator lint_on BLKSEQ


  //----------------------------------------------------------------------
  // Run the simulation
  //----------------------------------------------------------------------

  initial begin
    t.sim_begin();
    load_elf( t.elf_file );
  end

endmodule
