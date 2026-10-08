//========================================================================
// WritebackCommitUnitL5.v
//========================================================================
// A writeback unit that reorders messages based on sequence number
// (including physical register specifiers), forwards CSR operations and
// exceptions to the CSR file, and buffers stores: speculative stores in
// a store queue, and committed stores in a completed store buffer that
// retires them to memory (see STORE_QUEUE_DESIGN.md)

`ifndef HW_WRITEBACK_WRITEBACKCOMMITUNITVARIANTS_WRITEBACKCOMMITUNITL5_V
`define HW_WRITEBACK_WRITEBACKCOMMITUNITVARIANTS_WRITEBACKCOMMITUNITL5_V

`include "defs/CSRDefs.v"
`include "defs/UArch.v"
`include "hw/writeback_commit/ROB.v"
`include "hw/writeback_commit/StoreQueue.v"
`include "hw/writeback_commit/CompletedStoreBuffer.v"
`include "hw/util/SeqArb.v"
`include "intf/CompleteNotif.v"
`include "intf/CommitNotif.v"
`include "intf/CompletedStoreBufferIntf.v"
`include "intf/CSRNotif.v"
`include "intf/MemIntf.v"
`include "intf/SquashNotif.v"
`include "intf/StoreQueueIntf.v"
`include "intf/X__WIntf.v"

import CSRDefs::*;
import UArch::*;

module WritebackCommitUnitL5 #(
  parameter p_num_pipes = 1,
  parameter p_sq_depth  = 4,
  parameter p_csb_depth = 4,
  parameter p_opaq_bits = 8
)(
  input  logic clk,
  input  logic rst,

  //----------------------------------------------------------------------
  // X <-> W Interface
  //----------------------------------------------------------------------

  X__WIntf.W_intf Ex [p_num_pipes-1:0],

  //----------------------------------------------------------------------
  // Completion Interface
  //----------------------------------------------------------------------

  CompleteNotif.pub complete,

  //----------------------------------------------------------------------
  // Commit Interface
  //----------------------------------------------------------------------

  CommitNotif.pub   commit,

  //----------------------------------------------------------------------
  // CSR Interface
  //----------------------------------------------------------------------
  // Commit-time actions (CSR operations and exceptions)

  CSRNotif.pub      csr_notif,

  //----------------------------------------------------------------------
  // Squash Notification
  //----------------------------------------------------------------------

  SquashNotif.sub   squash,

  //----------------------------------------------------------------------
  // Store Queue (allocate, fill, search)
  //----------------------------------------------------------------------

  StoreQueueIntf.SQ_intf sq,

  //----------------------------------------------------------------------
  // Completed Store Buffer (search)
  //----------------------------------------------------------------------

  CompletedStoreBufferIntf.CSB_intf csb,

  //----------------------------------------------------------------------
  // Store Memory Interface (retire)
  //----------------------------------------------------------------------

  MemIntf.client    store_mem
);

  localparam p_seq_num_bits   = complete.p_seq_num_bits;
  localparam p_phys_addr_bits = complete.p_phys_addr_bits;

  //----------------------------------------------------------------------
  // Select which pipe to get from
  //----------------------------------------------------------------------

  logic                 [31:0] Ex_pc      [p_num_pipes-1:0];
  logic   [p_seq_num_bits-1:0] Ex_seq_num [p_num_pipes-1:0];
  logic                  [4:0] Ex_waddr   [p_num_pipes-1:0];
  logic                 [31:0] Ex_wdata   [p_num_pipes-1:0];
  logic                        Ex_wen     [p_num_pipes-1:0];
  logic [p_phys_addr_bits-1:0] Ex_preg    [p_num_pipes-1:0];
  logic [p_phys_addr_bits-1:0] Ex_ppreg   [p_num_pipes-1:0];
  logic                        Ex_val     [p_num_pipes-1:0];
  logic                        Ex_rdy     [p_num_pipes-1:0];
  logic                  [2:0] Ex_csr_cmd   [p_num_pipes-1:0];
  logic                 [11:0] Ex_csr_addr  [p_num_pipes-1:0];
  logic                 [31:0] Ex_csr_wdata [p_num_pipes-1:0];
  logic                        Ex_exc_val   [p_num_pipes-1:0];
  logic                  [4:0] Ex_exc_cause [p_num_pipes-1:0];

  genvar i;
  generate
    for( i = 0; i < p_num_pipes; i = i + 1 ) begin: UNPACK_FROM_INTF
      assign Ex_pc[i]      = Ex[i].pc;
      assign Ex_seq_num[i] = Ex[i].seq_num;
      assign Ex_waddr[i]   = Ex[i].waddr;
      assign Ex_wdata[i]   = Ex[i].wdata;
      assign Ex_wen[i]     = Ex[i].wen;
      assign Ex_preg[i]    = Ex[i].preg;
      assign Ex_ppreg[i]   = Ex[i].ppreg;
      assign Ex_val[i]     = Ex[i].val;
      assign Ex_csr_cmd[i]   = Ex[i].csr_cmd;
      assign Ex_csr_addr[i]  = Ex[i].csr_addr;
      assign Ex_csr_wdata[i] = Ex[i].csr_wdata;
      assign Ex_exc_val[i]   = Ex[i].exc_val;
      assign Ex_exc_cause[i] = Ex[i].exc_cause;
      assign Ex[i].rdy     = Ex_rdy[i];
    end
  endgenerate

  logic  Ex_gnt [p_num_pipes-1:0];

  CommitNotif #(
    .p_seq_num_bits   (p_seq_num_bits),
    .p_phys_addr_bits (commit.p_phys_addr_bits)
  ) local_commit();

  SeqArb #(
    .p_seq_num_bits (p_seq_num_bits),
    .p_num_arb      (p_num_pipes)
  ) ex_arb (
    .clk     (clk),
    .rst     (rst),
    .seq_num (Ex_seq_num),
    .val     (Ex_val),
    .gnt     (Ex_gnt),
    .commit  (local_commit)
  );

  logic                 [31:0] Ex_pc_masked      [p_num_pipes-1:0];
  logic   [p_seq_num_bits-1:0] Ex_seq_num_masked [p_num_pipes-1:0];
  logic                  [4:0] Ex_waddr_masked   [p_num_pipes-1:0];
  logic                 [31:0] Ex_wdata_masked   [p_num_pipes-1:0];
  logic                        Ex_wen_masked     [p_num_pipes-1:0];
  logic [p_phys_addr_bits-1:0] Ex_preg_masked    [p_num_pipes-1:0];
  logic [p_phys_addr_bits-1:0] Ex_ppreg_masked   [p_num_pipes-1:0];
  logic                        Ex_val_masked     [p_num_pipes-1:0];
  logic                  [2:0] Ex_csr_cmd_masked   [p_num_pipes-1:0];
  logic                 [11:0] Ex_csr_addr_masked  [p_num_pipes-1:0];
  logic                 [31:0] Ex_csr_wdata_masked [p_num_pipes-1:0];
  logic                        Ex_exc_val_masked   [p_num_pipes-1:0];
  logic                  [4:0] Ex_exc_cause_masked [p_num_pipes-1:0];

  generate
    for( i = 0; i < p_num_pipes; i = i + 1 ) begin: MASK
      assign Ex_pc_masked[i]      = Ex_pc[i]      & {32{Ex_gnt[i]}};
      assign Ex_seq_num_masked[i] = Ex_seq_num[i] & {p_seq_num_bits{Ex_gnt[i]}};
      assign Ex_waddr_masked[i]   = Ex_waddr[i]   & {5{Ex_gnt[i]}};
      assign Ex_wdata_masked[i]   = Ex_wdata[i]   & {32{Ex_gnt[i]}};
      assign Ex_wen_masked[i]     = Ex_wen[i]     & Ex_gnt[i];
      assign Ex_preg_masked[i]    = Ex_preg[i]    & {p_phys_addr_bits{Ex_gnt[i]}};
      assign Ex_ppreg_masked[i]   = Ex_ppreg[i]   & {p_phys_addr_bits{Ex_gnt[i]}};
      assign Ex_val_masked[i]     = Ex_val[i]     & Ex_gnt[i];
      assign Ex_csr_cmd_masked[i]   = Ex_csr_cmd[i]   & {3{Ex_gnt[i]}};
      assign Ex_csr_addr_masked[i]  = Ex_csr_addr[i]  & {12{Ex_gnt[i]}};
      assign Ex_csr_wdata_masked[i] = Ex_csr_wdata[i] & {32{Ex_gnt[i]}};
      assign Ex_exc_val_masked[i]   = Ex_exc_val[i]   & Ex_gnt[i];
      assign Ex_exc_cause_masked[i] = Ex_exc_cause[i] & {5{Ex_gnt[i]}};
    end
  endgenerate

  logic                 [31:0] Ex_pc_sel;
  logic   [p_seq_num_bits-1:0] Ex_seq_num_sel;
  logic                  [4:0] Ex_waddr_sel;
  logic                 [31:0] Ex_wdata_sel;
  logic                        Ex_wen_sel;
  logic [p_phys_addr_bits-1:0] Ex_preg_sel;
  logic [p_phys_addr_bits-1:0] Ex_ppreg_sel;
  logic                        Ex_val_sel;
  logic                  [2:0] Ex_csr_cmd_sel;
  logic                 [11:0] Ex_csr_addr_sel;
  logic                 [31:0] Ex_csr_wdata_sel;
  logic                        Ex_exc_val_sel;
  logic                  [4:0] Ex_exc_cause_sel;

`ifndef SYNTHESIS
  assign Ex_pc_sel      = Ex_pc_masked.or();
  assign Ex_seq_num_sel = Ex_seq_num_masked.or();
  assign Ex_waddr_sel   = Ex_waddr_masked.or();
  assign Ex_wdata_sel   = Ex_wdata_masked.or();
  assign Ex_wen_sel     = Ex_wen_masked.or();
  assign Ex_preg_sel    = Ex_preg_masked.or();
  assign Ex_ppreg_sel   = Ex_ppreg_masked.or();
  assign Ex_val_sel     = Ex_val_masked.or();
  assign Ex_csr_cmd_sel   = Ex_csr_cmd_masked.or();
  assign Ex_csr_addr_sel  = Ex_csr_addr_masked.or();
  assign Ex_csr_wdata_sel = Ex_csr_wdata_masked.or();
  assign Ex_exc_val_sel   = Ex_exc_val_masked.or();
  assign Ex_exc_cause_sel = Ex_exc_cause_masked.or();
`else
  always_comb begin
    Ex_pc_sel      = '0;
    Ex_seq_num_sel = '0;
    Ex_waddr_sel   = '0;
    Ex_wdata_sel   = '0;
    Ex_wen_sel     = '0;
    Ex_preg_sel    = '0;
    Ex_ppreg_sel   = '0;
    Ex_val_sel     = '0;
    Ex_csr_cmd_sel   = '0;
    Ex_csr_addr_sel  = '0;
    Ex_csr_wdata_sel = '0;
    Ex_exc_val_sel   = '0;
    Ex_exc_cause_sel = '0;
    
    for (int i = 0; i < p_num_pipes; i = i + 1) begin
      Ex_pc_sel      = Ex_pc_sel      | Ex_pc_masked[i];
      Ex_seq_num_sel = Ex_seq_num_sel | Ex_seq_num_masked[i];
      Ex_waddr_sel   = Ex_waddr_sel   | Ex_waddr_masked[i];
      Ex_wdata_sel   = Ex_wdata_sel   | Ex_wdata_masked[i];
      Ex_wen_sel     = Ex_wen_sel     | Ex_wen_masked[i];
      Ex_preg_sel    = Ex_preg_sel    | Ex_preg_masked[i];
      Ex_ppreg_sel   = Ex_ppreg_sel   | Ex_ppreg_masked[i];
      Ex_val_sel     = Ex_val_sel     | Ex_val_masked[i];
      Ex_csr_cmd_sel   = Ex_csr_cmd_sel   | Ex_csr_cmd_masked[i];
      Ex_csr_addr_sel  = Ex_csr_addr_sel  | Ex_csr_addr_masked[i];
      Ex_csr_wdata_sel = Ex_csr_wdata_sel | Ex_csr_wdata_masked[i];
      Ex_exc_val_sel   = Ex_exc_val_sel   | Ex_exc_val_masked[i];
      Ex_exc_cause_sel = Ex_exc_cause_sel | Ex_exc_cause_masked[i];
    end
  end
`endif // SYNTHESIS

  // No backpressure - always ready
  generate
    for( i = 0; i < p_num_pipes; i = i + 1 ) begin: ASSIGN_RDY
      assign Ex_rdy[i] = Ex_gnt[i];
    end
  endgenerate
  
  //----------------------------------------------------------------------
  // Pipeline registers for X interface
  //----------------------------------------------------------------------

  typedef struct packed {
    logic                        val;
    logic                 [31:0] pc;
    logic   [p_seq_num_bits-1:0] seq_num;
    logic                  [4:0] waddr;
    logic                 [31:0] wdata;
    logic                        wen;
    logic [p_phys_addr_bits-1:0] ppreg;
    logic                  [2:0] csr_cmd;
    logic                 [11:0] csr_addr;
    logic                 [31:0] csr_wdata;
    logic                        exc_val;
    logic                  [4:0] exc_cause;
  } X_input;

  X_input X_reg;
  X_input X_reg_next;

  always_ff @( posedge clk ) begin
    if ( rst )
      X_reg <= '{ 
        val: 1'b0, 
        pc: '0,
        seq_num: '0, 
        waddr: '0, 
        wdata: '0, 
        wen: 1'b0,
        ppreg: '0,
        csr_cmd: '0,
        csr_addr: '0,
        csr_wdata: '0,
        exc_val: 1'b0,
        exc_cause: '0
      };
    else
      X_reg <= X_reg_next;
  end

  always_comb begin
    if ( Ex_val_sel )
      X_reg_next = '{
        val:     1'b1,
        pc:      Ex_pc_sel,
        seq_num: Ex_seq_num_sel,
        waddr:   Ex_waddr_sel,
        wdata:   Ex_wdata_sel,
        wen:     Ex_wen_sel,
        ppreg:   Ex_ppreg_sel,
        csr_cmd:   Ex_csr_cmd_sel,
        csr_addr:  Ex_csr_addr_sel,
        csr_wdata: Ex_csr_wdata_sel,
        exc_val:   Ex_exc_val_sel,
        exc_cause: Ex_exc_cause_sel
      };
    else
      X_reg_next = '{ 
        val: 1'b0, 
        pc: '0,
        seq_num: '0, 
        waddr: '0, 
        wdata: '0, 
        wen: 1'b0,
        ppreg: '0,
        csr_cmd: '0,
        csr_addr: '0,
        csr_wdata: '0,
        exc_val: 1'b0,
        exc_cause: '0
      };
  end

  assign complete.val     = Ex_val_sel;
  assign complete.seq_num = Ex_seq_num_sel;
  assign complete.waddr   = Ex_waddr_sel;
  assign complete.wdata   = Ex_wdata_sel;
  assign complete.wen     = ( Ex_waddr_sel == '0 ) ? 0 : Ex_wen_sel;
  assign complete.preg    = Ex_preg_sel;

  //----------------------------------------------------------------------
  // ROB
  //----------------------------------------------------------------------

  typedef struct packed {
    logic                 [31:0] pc;
    logic                  [4:0] waddr;
    logic                 [31:0] wdata;
    logic                        wen;
    logic [p_phys_addr_bits-1:0] ppreg;
    logic                  [2:0] csr_cmd;
    logic                 [11:0] csr_addr;
    logic                 [31:0] csr_wdata;
    logic                        exc_val;
    logic                  [4:0] exc_cause;
  } t_rob_msg;

  t_rob_msg rob_input, rob_output;

  assign rob_input.pc      = X_reg.pc;
  assign rob_input.waddr   = X_reg.waddr;
  assign rob_input.wdata   = X_reg.wdata;
  assign rob_input.wen     = ( X_reg.waddr == '0 ) ? 0 : X_reg.wen;
  assign rob_input.ppreg   = X_reg.ppreg;
  assign rob_input.csr_cmd   = X_reg.csr_cmd;
  assign rob_input.csr_addr  = X_reg.csr_addr;
  assign rob_input.csr_wdata = X_reg.csr_wdata;
  assign rob_input.exc_val   = X_reg.exc_val;
  assign rob_input.exc_cause = X_reg.exc_cause;

  localparam p_rob_depth = 2 ** p_seq_num_bits;

  logic                      commit_ok;
  logic                      rob_deq_rdy;
  logic [p_seq_num_bits-1:0] rob_deq_idx;

  ROB #(
    .p_depth    (p_rob_depth),
    .p_msg_bits ($bits(t_rob_msg))
  ) rob (
    .ins_idx (X_reg.seq_num),
    .ins_msg (rob_input),
    .ins_en  (X_reg.val),

    .deq_idx (rob_deq_idx),
    .deq_msg (rob_output),
    .deq_en  (commit_ok),
    .deq_rdy (rob_deq_rdy),
    .*
  );

  //----------------------------------------------------------------------
  // Store Queue and Completed Store Buffer
  //----------------------------------------------------------------------

  generate
    if( sq.p_sq_idx_bits != $clog2( p_sq_depth ) ) begin: BAD_SQ_IDX_BITS
      $error( "WritebackCommitUnitL5: StoreQueueIntf p_sq_idx_bits must be $clog2(p_sq_depth)" );
    end
  endgenerate

  logic                      sq_deq_en;
  logic                      sq_deq_rdy;
  logic [p_seq_num_bits-1:0] sq_deq_seq_num;
  logic               [31:2] sq_deq_addr;
  logic                [3:0] sq_deq_strb;
  logic               [31:0] sq_deq_data;

  StoreQueue #(
    .p_depth        (p_sq_depth),
    .p_seq_num_bits (p_seq_num_bits)
  ) store_queue (
    .clk         (clk),
    .rst         (rst),
    .sq          (sq),
    .squash      (squash),
    .commit      (local_commit),
    .deq_en      (sq_deq_en),
    .deq_rdy     (sq_deq_rdy),
    .deq_seq_num (sq_deq_seq_num),
    .deq_addr    (sq_deq_addr),
    .deq_strb    (sq_deq_strb),
    .deq_data    (sq_deq_data)
  );

  logic csb_push_en;
  logic csb_push_rdy;

  CompletedStoreBuffer #(
    .p_depth     (p_csb_depth),
    .p_opaq_bits (p_opaq_bits)
  ) completed_store_buffer (
    .clk       (clk),
    .rst       (rst),
    .csb       (csb),
    .mem       (store_mem),
    .push_en   (csb_push_en),
    .push_addr (sq_deq_addr),
    .push_strb (sq_deq_strb),
    .push_data (sq_deq_data),
    .push_rdy  (csb_push_rdy)
  );

  //----------------------------------------------------------------------
  // Commit
  //----------------------------------------------------------------------
  // The ROB head is a store exactly when its sequence number matches the
  // store queue head's. A store commits only if the completed store
  // buffer can accept it; an excepting store is dequeued but dropped.

  logic head_is_store;

  assign head_is_store = sq_deq_rdy & ( sq_deq_seq_num == rob_deq_idx );
  assign commit_ok     = rob_deq_rdy & ( !head_is_store | csb_push_rdy );
  assign sq_deq_en     = commit_ok & head_is_store;
  assign csb_push_en   = sq_deq_en & !rob_output.exc_val;

  assign commit.val     = commit_ok;
  assign commit.seq_num = rob_deq_idx;

  assign commit.pc    = rob_output.pc;
  assign commit.waddr = rob_output.waddr;
  assign commit.wdata = rob_output.wdata;
  assign commit.wen   = rob_output.wen;
  assign commit.ppreg = rob_output.ppreg;

  //----------------------------------------------------------------------
  // Commit-time action, applied to the CSR file
  //----------------------------------------------------------------------

  assign csr_notif.val       = commit.val & ( rob_output.exc_val |
                                              ( rob_output.csr_cmd != CSR_CMD_NONE ) );
  assign csr_notif.cmd       = rob_output.csr_cmd;
  assign csr_notif.addr      = rob_output.csr_addr;
  assign csr_notif.wdata     = rob_output.csr_wdata;
  assign csr_notif.exc_val   = rob_output.exc_val;
  assign csr_notif.exc_cause = rob_output.exc_cause;
  assign csr_notif.pc        = rob_output.pc;
  assign csr_notif.seq_num   = commit.seq_num;

  assign local_commit.val     = commit.val;
  assign local_commit.pc      = commit.pc;
  assign local_commit.seq_num = commit.seq_num;
  assign local_commit.waddr   = commit.waddr;
  assign local_commit.wdata   = commit.wdata;
  assign local_commit.wen     = commit.wen;
  assign local_commit.ppreg   = commit.ppreg;

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------

`ifndef SYNTHESIS
  function int ceil_div_4( int val );
    return (val / 4) + ((val % 4) > 0 ? 1 : 0);
  endfunction

  int str_len;
  assign str_len = ceil_div_4( p_seq_num_bits ) + 1 + // seq_num
                   1                            + 1 + // wen
                   ceil_div_4( 5 )              + 1 + // addr
                   8;                                 // data
  
  function string trace( int trace_level );
    if( X_reg.val ) begin
      if( trace_level > 0 )
        trace = $sformatf("%h:%h:%h:%h", X_reg.seq_num, X_reg.wen, X_reg.waddr, X_reg.wdata );
      else
        trace = $sformatf("%h", X_reg.seq_num);
    end else begin
      if( trace_level > 0 )
        trace = {str_len{" "}};
      else
        trace = {(ceil_div_4( p_seq_num_bits )){" "}};
    end

    // Store queue and completed store buffer occupancy
    trace = {trace, " ", store_queue.trace( trace_level ),
                    " ", completed_store_buffer.trace( trace_level )};
  endfunction
`endif

endmodule

`endif // HW_WRITEBACK_WRITEBACKCOMMITUNITVARIANTS_WRITEBACKCOMMITUNITL5_V
