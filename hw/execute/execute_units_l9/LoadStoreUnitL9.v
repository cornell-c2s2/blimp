//========================================================================
// LoadStoreUnitL9.v
//========================================================================
// An execute unit for performing memory operations, with stores
// buffered in a store queue until they commit (see
// STORE_QUEUE_DESIGN.md)
//
//  - Stores fill their store queue entry in stage 1 and complete without
//    accessing memory
//  - Loads search the store queue and the completed store buffer in
//    stage 1. Per byte lane, the youngest older store wins (the store
//    queue over the completed store buffer). A fully covered load skips
//    memory; a partly covered load merges the forwarded lanes over the
//    memory response
//
// The memory interface only issues reads.

`ifndef HW_EXECUTE_EXECUTE_VARIANTS_L9_LOADSTOREUNITL9_V
`define HW_EXECUTE_EXECUTE_VARIANTS_L9_LOADSTOREUNITL9_V

`include "defs/CSRDefs.v"
`include "defs/UArch.v"
`include "hw/common/Fifo.v"
`include "intf/CompletedStoreBufferIntf.v"
`include "intf/D__XIntf.v"
`include "intf/MemIntf.v"
`include "intf/StoreQueueIntf.v"
`include "intf/X__WIntf.v"

import CSRDefs::*;
import UArch::*;

module LoadStoreUnitL9 #(
  parameter p_opaq_bits     = 8,
  parameter p_num_in_flight = 8
)(
  input  logic clk,
  input  logic rst,

  //----------------------------------------------------------------------
  // D <-> X Interface
  //----------------------------------------------------------------------

  D__XIntf.X_intf D,

  //----------------------------------------------------------------------
  // X <-> W Interface
  //----------------------------------------------------------------------

  X__WIntf.X_intf W,

  //----------------------------------------------------------------------
  // Memory Interface (reads only)
  //----------------------------------------------------------------------

  MemIntf.client  mem,

  //----------------------------------------------------------------------
  // Store Queue (fill, search)
  //----------------------------------------------------------------------

  StoreQueueIntf.X_intf sq,

  //----------------------------------------------------------------------
  // Completed Store Buffer (search)
  //----------------------------------------------------------------------

  CompletedStoreBufferIntf.X_intf csb
);

  localparam p_seq_num_bits   = D.p_seq_num_bits;
  localparam p_phys_addr_bits = D.p_phys_addr_bits;
  localparam p_sq_idx_bits    = D.p_sq_idx_bits;

  //----------------------------------------------------------------------
  // Types
  //----------------------------------------------------------------------

  typedef struct packed {
    logic                        val;
    logic                 [31:0] pc;
    logic   [p_seq_num_bits-1:0] seq_num;
    logic                 [31:0] op1;
    logic                 [31:0] op2;
    logic                  [4:0] waddr;
    logic [p_phys_addr_bits-1:0] preg;
    logic [p_phys_addr_bits-1:0] ppreg;
    logic                 [31:0] mem_data;
    logic    [p_sq_idx_bits-1:0] sq_idx;
    rv_uop                       uop;
  } D_input;

  typedef struct packed {
    logic                        val;
    logic                 [31:0] pc;
    logic   [p_seq_num_bits-1:0] seq_num;
    logic                  [4:0] waddr;
    logic [p_phys_addr_bits-1:0] preg;
    logic [p_phys_addr_bits-1:0] ppreg;
    rv_uop                       uop;
    logic                  [1:0] offset;
    logic                        resp;     // A memory response is expected
    logic                  [3:0] fwd_mask; // Lanes forwarded from stores
    logic                 [31:0] fwd_data; // Forwarded lanes
  } stage2_msg;

  //----------------------------------------------------------------------
  // Stage 1: Request
  //----------------------------------------------------------------------

  D_input D_reg;
  D_input D_reg_next;
  logic   D_xfer;

  logic      stage2_rdy;
  stage2_msg stage2_reg;
  stage2_msg stage2_reg_next;
  logic      stage2_push, stage2_pop, stage2_empty, stage2_full;

  logic W_xfer;

  // verilator lint_off ENUMVALUE

  always_ff @( posedge clk ) begin
    if ( rst )
      D_reg <= '{
        val:      1'b0,
        pc:       '0,
        seq_num:  '0,
        op1:      '0,
        op2:      '0,
        waddr:    '0,
        preg:     '0,
        ppreg:    '0,
        mem_data: '0,
        sq_idx:   '0,
        uop:      rv_uop'('0)
      };
    else
      D_reg <= D_reg_next;
  end

  always_comb begin
    D_xfer = D.val & D.rdy;

    if ( D_xfer )
      D_reg_next = '{
        val:      1'b1,
        pc:       D.pc,
        seq_num:  D.seq_num,
        op1:      D.op1,
        op2:      D.op2,
        waddr:    D.waddr,
        preg:     D.preg,
        ppreg:    D.ppreg,
        mem_data: D.op3.mem_data,
        sq_idx:   D.sq_idx,
        uop:      D.uop
      };
    else if ( stage2_push )
      D_reg_next = '{
        val:      1'b0,
        pc:       '0,
        seq_num:  '0,
        op1:      '0,
        op2:      '0,
        waddr:    '0,
        preg:     '0,
        ppreg:    '0,
        mem_data: '0,
        sq_idx:   '0,
        uop:      rv_uop'('0)
      };
    else
      D_reg_next = D_reg;
  end

  // verilator lint_on ENUMVALUE

  //----------------------------------------------------------------------
  // Address, lanes and data
  //----------------------------------------------------------------------

  logic [31:0] op1, op2;
  assign op1 = D_reg.op1;
  assign op2 = D_reg.op2;

  logic [31:0] addr;
  assign addr = op1 + op2;

  rv_uop uop;
  assign uop = D_reg.uop;

  logic is_store;
  logic is_load;

  always_comb begin
    case( uop )
      OP_LB, OP_LH, OP_LW, OP_LBU, OP_LHU: begin
        is_store = 1'b0;
        is_load  = 1'b1;
      end
      OP_SB, OP_SH, OP_SW: begin
        is_store = 1'b1;
        is_load  = 1'b0;
      end
      default: begin
        is_store = 1'b0;
        is_load  = 1'b0;
      end
    endcase
  end

  logic [3:0] base_strb;

  always_comb begin
    case( uop )
      OP_LB:   base_strb = 4'b0001;
      OP_LH:   base_strb = 4'b0011;
      OP_LW:   base_strb = 4'b1111;
      OP_LBU:  base_strb = 4'b0001;
      OP_LHU:  base_strb = 4'b0011;
      OP_SB:   base_strb = 4'b0001;
      OP_SH:   base_strb = 4'b0011;
      OP_SW:   base_strb = 4'b1111;
      default: base_strb = 'x;
    endcase
  end

  // Decompose address
  logic [31:2] word_addr;
  logic  [1:0] stage1_addr_offset;
  logic  [3:0] strb;

  assign word_addr          = addr[31:2];
  assign stage1_addr_offset = addr[1:0];
  assign strb               = base_strb << stage1_addr_offset;

  // Lane-aligned store data
  logic [31:0] store_data;

  always_comb begin
    case( stage1_addr_offset )
      2'd0: store_data = D_reg.mem_data;
      2'd1: store_data = D_reg.mem_data << 8;
      2'd2: store_data = D_reg.mem_data << 16;
      2'd3: store_data = D_reg.mem_data << 24;
    endcase
  end

  //----------------------------------------------------------------------
  // Store: fill the store queue
  //----------------------------------------------------------------------
  // A store fills in the cycle it leaves stage 1

  assign sq.fill_val  = D_reg.val & is_store & stage2_push;
  assign sq.fill_idx  = D_reg.sq_idx;
  assign sq.fill_addr = word_addr;
  assign sq.fill_strb = strb;
  assign sq.fill_data = store_data;

  //----------------------------------------------------------------------
  // Load: search the store queue and the completed store buffer
  //----------------------------------------------------------------------
  // Every store queue entry is younger than every completed store buffer
  // entry, so per lane the store queue takes priority

  assign sq.search_addr  = word_addr;
  assign csb.search_addr = word_addr;

  logic  [3:0] fwd_hit;
  logic [31:0] fwd_data;
  logic  [3:0] fwd_cover;
  logic        need_mem;

  genvar l;
  generate
    for( l = 0; l < 4; l = l + 1 ) begin: FWD_LANE
      assign fwd_data[8*l +: 8] = ( sq.search_hit[l] ) ? sq.search_data[8*l +: 8]
                                                       : csb.search_data[8*l +: 8];
    end
  endgenerate

  assign fwd_hit   = sq.search_hit | csb.search_hit;
  assign fwd_cover = fwd_hit & strb;
  assign need_mem  = is_load & ( fwd_cover != strb );

  //----------------------------------------------------------------------
  // Memory request (reads only)
  //----------------------------------------------------------------------

  assign mem.req_msg.op     = MEM_MSG_READ;
  assign mem.req_msg.opaque = '0;
  assign mem.req_msg.addr   = { word_addr, 2'b00 };
  assign mem.req_msg.strb   = strb;
  assign mem.req_msg.data   = '0;
  assign mem.req_val        = D_reg.val & need_mem & stage2_rdy;

  //----------------------------------------------------------------------
  // In-flight FIFO
  //----------------------------------------------------------------------

  stage2_msg stage1_output;

  assign stage1_output.val      = D_reg.val;
  assign stage1_output.pc       = D_reg.pc;
  assign stage1_output.seq_num  = D_reg.seq_num;
  assign stage1_output.waddr    = D_reg.waddr;
  assign stage1_output.uop      = uop;
  assign stage1_output.offset   = stage1_addr_offset;
  assign stage1_output.preg     = D_reg.preg;
  assign stage1_output.ppreg    = D_reg.ppreg;
  assign stage1_output.resp     = need_mem;
  assign stage1_output.fwd_mask = ( is_load ) ? fwd_cover : 4'b0;
  assign stage1_output.fwd_data = fwd_data;

  assign stage2_rdy  = !stage2_full;
  assign stage2_push = D_reg.val & stage2_rdy & ( !need_mem | mem.req_rdy );
  assign D.rdy       = !D_reg.val | stage2_push;

  stage2_msg stage2_input;

  Fifo #(
    .p_entry_bits ($bits(stage2_msg)),
    .p_depth      (p_num_in_flight) // Must be at least as long as memory pipeline
  ) stage2_fifo (
    .clk   (clk),
    .rst   (rst),
    .push  (stage2_push),
    .pop   (stage2_pop),
    .empty (stage2_empty),
    .full  (stage2_full),
    .wdata (stage1_output),
    .rdata (stage2_input)
  );

  //----------------------------------------------------------------------
  // Stage 2: Response
  //----------------------------------------------------------------------

  // verilator lint_off ENUMVALUE
  always_ff @( posedge clk ) begin
    if ( rst )
      stage2_reg <= '{
        val:      1'b0,
        pc:       '0,
        seq_num:  '0,
        waddr:    '0,
        preg:     '0,
        ppreg:    '0,
        uop:      rv_uop'('0),
        offset:   '0,
        resp:     1'b0,
        fwd_mask: '0,
        fwd_data: '0
      };
    else
      stage2_reg <= stage2_reg_next;
  end

  always_comb begin
    W_xfer = W.val & W.rdy;

    if ( stage2_pop )
      stage2_reg_next = stage2_input;
    else if ( W_xfer )
      stage2_reg_next = '{
        val:      1'b0,
        pc:       '0,
        seq_num:  '0,
        waddr:    '0,
        preg:     '0,
        ppreg:    '0,
        uop:      rv_uop'('0),
        offset:   '0,
        resp:     1'b0,
        fwd_mask: '0,
        fwd_data: '0
      };
    else
      stage2_reg_next = stage2_reg;
  end
  // verilator lint_on ENUMVALUE

  //----------------------------------------------------------------------
  // Determine correct data
  //----------------------------------------------------------------------
  // Forwarded lanes override the memory response. With no response, every
  // lane the load reads is forwarded; the other lanes are don't-care

  logic [31:0] merged_data;

  generate
    for( l = 0; l < 4; l = l + 1 ) begin: MERGE_LANE
      assign merged_data[8*l +: 8] = ( stage2_reg.fwd_mask[l] ) ? stage2_reg.fwd_data[8*l +: 8]
                                                                : mem.resp_msg.data[8*l +: 8];
    end
  endgenerate

  logic [31:0] base_data, sext_data;
  always_comb begin
    case( stage2_reg.offset )
      2'd0: base_data = merged_data;
      2'd1: base_data = merged_data >> 8;
      2'd2: base_data = merged_data >> 16;
      2'd3: base_data = merged_data >> 24;
    endcase
  end

  always_comb begin
    case( stage2_reg.uop )
      OP_LB:   sext_data = { {24{base_data[7] }}, base_data[7:0]  };
      OP_LH:   sext_data = { {16{base_data[15]}}, base_data[15:0] };
      OP_LW:   sext_data = base_data;
      OP_LBU:  sext_data = { 24'b0, base_data[7:0]  };
      OP_LHU:  sext_data = { 16'b0, base_data[15:0] };
      OP_SB:   sext_data = '0;
      OP_SH:   sext_data = '0;
      OP_SW:   sext_data = '0;
      default: sext_data = '0;
    endcase
  end

  //----------------------------------------------------------------------
  // Writeback
  //----------------------------------------------------------------------

  t_op                    unused_resp_op;
  logic [p_opaq_bits-1:0] unused_resp_opaque;
  logic            [31:0] unused_resp_addr;
  logic             [3:0] unused_resp_strb;

  assign unused_resp_op     = mem.resp_msg.op;
  assign unused_resp_opaque = mem.resp_msg.opaque;
  assign unused_resp_addr   = mem.resp_msg.addr;
  assign unused_resp_strb   = mem.resp_msg.strb;
  assign W.wdata            = sext_data;

  assign W.pc               = stage2_reg.pc;
  assign W.waddr            = stage2_reg.waddr;
  assign W.seq_num          = stage2_reg.seq_num;
  assign W.preg             = stage2_reg.preg;
  assign W.ppreg            = stage2_reg.ppreg;

  assign W.csr_cmd          = CSR_CMD_NONE;
  assign W.csr_addr         = 12'b0;
  assign W.csr_wdata        = 32'b0;
  assign W.exc_val          = 1'b0;
  assign W.exc_cause        = 5'b0;

  always_comb begin
    case( stage2_reg.uop )
      OP_LB:   W.wen = 1'b1;
      OP_LH:   W.wen = 1'b1;
      OP_LW:   W.wen = 1'b1;
      OP_LBU:  W.wen = 1'b1;
      OP_LHU:  W.wen = 1'b1;
      OP_SB:   W.wen = 1'b0;
      OP_SH:   W.wen = 1'b0;
      OP_SW:   W.wen = 1'b0;
      default: W.wen = 1'bx;
    endcase
  end

  assign mem.resp_rdy = stage2_reg.val & stage2_reg.resp & W.rdy;
  assign W.val        = stage2_reg.val & ( !stage2_reg.resp | mem.resp_val );
  assign stage2_pop   = ( W_xfer | !stage2_reg.val ) & !stage2_empty;

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------
  // The request side marks a store fill with "s", and a load's forwarding
  // with "F" (all lanes), "P" (some lanes) or "-" (none)

`ifndef SYNTHESIS
  function int ceil_div_4( int val );
    return (val / 4) + ((val % 4) > 0 ? 1 : 0);
  endfunction

  int req_len;
  assign req_len = 11                         + 1 + // uop
                   ceil_div_4(p_seq_num_bits) + 1 + // seq_num
                   8                          + 1 + // addr
                   8                          + 1 + // data
                   1;                               // forwarding

  int resp_len;
  assign resp_len = 11                         + 1 + // uop
                    ceil_div_4(p_seq_num_bits) + 1 + // seq_num
                    8;                               // data

  function string fwd_char();
    if( is_store )
      return "s";
    else if( fwd_cover == strb )
      return "F";
    else if( fwd_cover != 4'b0 )
      return "P";
    else
      return "-";
  endfunction

  function string trace( int trace_level );
    if( stage2_push ) begin
      if( trace_level > 0 )
        trace = $sformatf("%11s:%h:%h:%h:%s", uop.name(),
                          D_reg.seq_num, addr, D_reg.mem_data, fwd_char() );
      else
        trace = $sformatf("%h", D_reg.seq_num);
    end else begin
      if( trace_level > 0 )
        trace = {req_len{" "}};
      else
        trace = {(ceil_div_4(p_seq_num_bits)){" "}};
    end

    trace = {trace, " > "};

    if( W.val & W.rdy ) begin
      if( trace_level > 0 )
        trace = {trace, $sformatf("%11s:%h:%h",
                      stage2_reg.uop.name(),
                      stage2_reg.seq_num, W.wdata )};
      else
        trace = {trace, $sformatf("%h", stage2_reg.seq_num)};
    end else begin
      if( trace_level > 0 )
        trace = {trace, {resp_len{" "}}};
      else
        trace = {trace, {(ceil_div_4(p_seq_num_bits)){" "}}};
    end
  endfunction
`endif

endmodule

`endif // HW_EXECUTE_EXECUTE_VARIANTS_L9_LOADSTOREUNITL9_V
