//========================================================================
// BlimpV8_sp26_sim.v
//========================================================================
// A module for simulating BlimpV8_sp26 for SP26 tapein 1

`include "asm/assemble.v"
`include "intf/mem_intf.sv"
`include "intf/mem_net_req.sv"
`include "intf/mem_net_resp.sv"
`include "top/sp26/rtl/tapein1/mem_xbar.sv"

`include "sram/SRAMMem.v"

`include "fpga/net/MemNetReq.v"
`include "fpga/net/MemNetResp.v"
`include "hw/top/BlimpV8_sp26.v"
`include "hw/top/sim/utils/SimUtils.v"
`include "intf/MemIntf.v"
`include "intf/InstTraceNotif.v"
`include "hw/top/sim/utils/FLPeripherals.v"

import "DPI-C" context function void load_elf ( string elf_file );

module BlimpV8_sp26_sim;

  // Define default simulation parameters
  localparam p_num_phys_regs = 36;
  localparam p_opaq_bits     = 8;
  localparam p_seq_num_bits  = 5;
  localparam p_num_entries   = 2048;
  localparam p_num_bits      = $clog2( p_num_entries );
  localparam p_max_in_flight = 1;
  
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
  ) mem_intf[2]();

  intf_MemIntf #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_mem_intf[2]();
  
  InstTraceNotif inst_trace_notif();

  BlimpV8_sp26 #(
    .p_opaq_bits     (p_opaq_bits),
    .p_seq_num_bits  (p_seq_num_bits),
    .p_num_phys_regs (p_num_phys_regs),
    .p_max_in_flight (p_max_in_flight)
  ) dut (
    .inst_mem   (mem_intf[0]),
    .data_mem   (mem_intf[1]),
    .inst_trace (inst_trace_notif),
    .inst_trace_deq_rdy (1),
    .debug              (0),
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
  // Memory Subsystem
  //----------------------------------------------------------------------

  MemIntf #(
    .p_opaq_bits (p_opaq_bits) 
  ) spi_intf();
  MemIntf #(
    .p_opaq_bits (p_opaq_bits)
  ) sysarr_intf();

  intf_MemIntf #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_spi_intf();
  intf_MemIntf #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_sysarr_intf();

  MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) sram_req();
  MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) mem_ctrl_req();
  MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) cpu_ctrl_req();
  MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) sysarr_ctrl_req();
  MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) peripheral_req();

  intf_MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_sram_req();
  intf_MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_mem_ctrl_req();
  intf_MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_cpu_ctrl_req();
  intf_MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_sysarr_ctrl_req();
  intf_MemNetReq #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_peripheral_req();

  MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) sram_resp();
  MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) mem_ctrl_resp();
  MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) cpu_ctrl_resp();
  MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) sysarr_ctrl_resp();
  MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) peripheral_resp();

  intf_MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_sram_resp();
  intf_MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_mem_ctrl_resp();
  intf_MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_cpu_ctrl_resp();
  intf_MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_sysarr_ctrl_resp();
  intf_MemNetResp #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar_peripheral_resp();

  // ---------------------------------------------------------------------
  // Bridge BLIMP interfaces to top/sp26 interfaces for xbar compatibility
  // ---------------------------------------------------------------------

  // Processor instruction memory interface bridge
  assign xbar_mem_intf[0].req_val        = mem_intf[0].req_val;
  assign xbar_mem_intf[0].req_msg.op     = mem_op'(mem_intf[0].req_msg.op == MEM_MSG_WRITE ? MEMORY_MSG_WRITE :
                                                    (mem_intf[0].req_msg.op == MEM_MSG_READ ? MEMORY_MSG_READ : MEMORY_MSG_X));
  assign xbar_mem_intf[0].req_msg.opaque = mem_intf[0].req_msg.opaque;
  assign xbar_mem_intf[0].req_msg.addr   = mem_intf[0].req_msg.addr;
  assign xbar_mem_intf[0].req_msg.strb   = mem_intf[0].req_msg.strb;
  assign xbar_mem_intf[0].req_msg.data   = mem_intf[0].req_msg.data;
  assign mem_intf[0].req_rdy             = xbar_mem_intf[0].req_rdy;

  assign mem_intf[0].resp_val            = xbar_mem_intf[0].resp_val;
  assign mem_intf[0].resp_msg.op         = t_op'(xbar_mem_intf[0].resp_msg.op == MEMORY_MSG_WRITE ? MEM_MSG_WRITE :
                                                  (xbar_mem_intf[0].resp_msg.op == MEMORY_MSG_READ ? MEM_MSG_READ : 1'bx));
  assign mem_intf[0].resp_msg.opaque     = xbar_mem_intf[0].resp_msg.opaque;
  assign mem_intf[0].resp_msg.addr       = xbar_mem_intf[0].resp_msg.addr;
  assign mem_intf[0].resp_msg.strb       = xbar_mem_intf[0].resp_msg.strb;
  assign mem_intf[0].resp_msg.data       = xbar_mem_intf[0].resp_msg.data;
  assign xbar_mem_intf[0].resp_rdy       = mem_intf[0].resp_rdy;

  // Processor data memory interface bridge
  assign xbar_mem_intf[1].req_val        = mem_intf[1].req_val;
  assign xbar_mem_intf[1].req_msg.op     = mem_op'(mem_intf[1].req_msg.op == MEM_MSG_WRITE ? MEMORY_MSG_WRITE :
                                                    (mem_intf[1].req_msg.op == MEM_MSG_READ ? MEMORY_MSG_READ : MEMORY_MSG_X));
  assign xbar_mem_intf[1].req_msg.opaque = mem_intf[1].req_msg.opaque;
  assign xbar_mem_intf[1].req_msg.addr   = mem_intf[1].req_msg.addr;
  assign xbar_mem_intf[1].req_msg.strb   = mem_intf[1].req_msg.strb;
  assign xbar_mem_intf[1].req_msg.data   = mem_intf[1].req_msg.data;
  assign mem_intf[1].req_rdy             = xbar_mem_intf[1].req_rdy;

  assign mem_intf[1].resp_val            = xbar_mem_intf[1].resp_val;
  assign mem_intf[1].resp_msg.op         = t_op'(xbar_mem_intf[1].resp_msg.op == MEMORY_MSG_WRITE ? MEM_MSG_WRITE :
                                                  (xbar_mem_intf[1].resp_msg.op == MEMORY_MSG_READ ? MEM_MSG_READ : 1'bx));
  assign mem_intf[1].resp_msg.opaque     = xbar_mem_intf[1].resp_msg.opaque;
  assign mem_intf[1].resp_msg.addr       = xbar_mem_intf[1].resp_msg.addr;
  assign mem_intf[1].resp_msg.strb       = xbar_mem_intf[1].resp_msg.strb;
  assign mem_intf[1].resp_msg.data       = xbar_mem_intf[1].resp_msg.data;
  assign xbar_mem_intf[1].resp_rdy       = mem_intf[1].resp_rdy;

  // SPI interface bridge
  assign xbar_spi_intf.req_val        = spi_intf.req_val;
  assign xbar_spi_intf.req_msg.op     = mem_op'(spi_intf.req_msg.op == MEM_MSG_WRITE ? MEMORY_MSG_WRITE :
                                                 (spi_intf.req_msg.op == MEM_MSG_READ ? MEMORY_MSG_READ : MEMORY_MSG_X));
  assign xbar_spi_intf.req_msg.opaque = spi_intf.req_msg.opaque;
  assign xbar_spi_intf.req_msg.addr   = spi_intf.req_msg.addr;
  assign xbar_spi_intf.req_msg.strb   = spi_intf.req_msg.strb;
  assign xbar_spi_intf.req_msg.data   = spi_intf.req_msg.data;
  assign spi_intf.req_rdy             = xbar_spi_intf.req_rdy;

  assign spi_intf.resp_val            = xbar_spi_intf.resp_val;
  assign spi_intf.resp_msg.op         = t_op'(xbar_spi_intf.resp_msg.op == MEMORY_MSG_WRITE ? MEM_MSG_WRITE :
                                               (xbar_spi_intf.resp_msg.op == MEMORY_MSG_READ ? MEM_MSG_READ : 1'bx));
  assign spi_intf.resp_msg.opaque     = xbar_spi_intf.resp_msg.opaque;
  assign spi_intf.resp_msg.addr       = xbar_spi_intf.resp_msg.addr;
  assign spi_intf.resp_msg.strb       = xbar_spi_intf.resp_msg.strb;
  assign spi_intf.resp_msg.data       = xbar_spi_intf.resp_msg.data;
  assign xbar_spi_intf.resp_rdy       = spi_intf.resp_rdy;

  // Systolic array interface bridge
  assign xbar_sysarr_intf.req_val        = sysarr_intf.req_val;
  assign xbar_sysarr_intf.req_msg.op     = mem_op'(sysarr_intf.req_msg.op == MEM_MSG_WRITE ? MEMORY_MSG_WRITE :
                                                    (sysarr_intf.req_msg.op == MEM_MSG_READ ? MEMORY_MSG_READ : MEMORY_MSG_X));
  assign xbar_sysarr_intf.req_msg.opaque = sysarr_intf.req_msg.opaque;
  assign xbar_sysarr_intf.req_msg.addr   = sysarr_intf.req_msg.addr;
  assign xbar_sysarr_intf.req_msg.strb   = sysarr_intf.req_msg.strb;
  assign xbar_sysarr_intf.req_msg.data   = sysarr_intf.req_msg.data;
  assign sysarr_intf.req_rdy             = xbar_sysarr_intf.req_rdy;

  assign sysarr_intf.resp_val            = xbar_sysarr_intf.resp_val;
  assign sysarr_intf.resp_msg.op         = t_op'(xbar_sysarr_intf.resp_msg.op == MEMORY_MSG_WRITE ? MEM_MSG_WRITE :
                                                  (xbar_sysarr_intf.resp_msg.op == MEMORY_MSG_READ ? MEM_MSG_READ : 1'bx));
  assign sysarr_intf.resp_msg.opaque     = xbar_sysarr_intf.resp_msg.opaque;
  assign sysarr_intf.resp_msg.addr       = xbar_sysarr_intf.resp_msg.addr;
  assign sysarr_intf.resp_msg.strb       = xbar_sysarr_intf.resp_msg.strb;
  assign sysarr_intf.resp_msg.data       = xbar_sysarr_intf.resp_msg.data;
  assign xbar_sysarr_intf.resp_rdy       = sysarr_intf.resp_rdy;

  // MemNet request interface bridges
  assign sram_req.val                 = xbar_sram_req.val;
  assign sram_req.msg.op              = t_op'(xbar_sram_req.msg.op == MEMORY_MSG_WRITE ? MEM_MSG_WRITE :
                                               (xbar_sram_req.msg.op == MEMORY_MSG_READ ? MEM_MSG_READ : 1'bx));
  assign sram_req.msg.opaque          = xbar_sram_req.msg.opaque;
  assign sram_req.msg.origin          = xbar_sram_req.msg.origin;
  assign sram_req.msg.addr            = xbar_sram_req.msg.addr;
  assign sram_req.msg.strb            = xbar_sram_req.msg.strb;
  assign sram_req.msg.data            = xbar_sram_req.msg.data;
  assign xbar_sram_req.rdy            = sram_req.rdy;

  assign mem_ctrl_req.val             = xbar_mem_ctrl_req.val;
  assign mem_ctrl_req.msg.op          = t_op'(xbar_mem_ctrl_req.msg.op == MEMORY_MSG_WRITE ? MEM_MSG_WRITE :
                                               (xbar_mem_ctrl_req.msg.op == MEMORY_MSG_READ ? MEM_MSG_READ : 1'bx));
  assign mem_ctrl_req.msg.opaque      = xbar_mem_ctrl_req.msg.opaque;
  assign mem_ctrl_req.msg.origin      = xbar_mem_ctrl_req.msg.origin;
  assign mem_ctrl_req.msg.addr        = xbar_mem_ctrl_req.msg.addr;
  assign mem_ctrl_req.msg.strb        = xbar_mem_ctrl_req.msg.strb;
  assign mem_ctrl_req.msg.data        = xbar_mem_ctrl_req.msg.data;
  assign xbar_mem_ctrl_req.rdy        = mem_ctrl_req.rdy;

  assign cpu_ctrl_req.val             = xbar_cpu_ctrl_req.val;
  assign cpu_ctrl_req.msg.op          = t_op'(xbar_cpu_ctrl_req.msg.op == MEMORY_MSG_WRITE ? MEM_MSG_WRITE :
                                               (xbar_cpu_ctrl_req.msg.op == MEMORY_MSG_READ ? MEM_MSG_READ : 1'bx));
  assign cpu_ctrl_req.msg.opaque      = xbar_cpu_ctrl_req.msg.opaque;
  assign cpu_ctrl_req.msg.origin      = xbar_cpu_ctrl_req.msg.origin;
  assign cpu_ctrl_req.msg.addr        = xbar_cpu_ctrl_req.msg.addr;
  assign cpu_ctrl_req.msg.strb        = xbar_cpu_ctrl_req.msg.strb;
  assign cpu_ctrl_req.msg.data        = xbar_cpu_ctrl_req.msg.data;
  assign xbar_cpu_ctrl_req.rdy        = cpu_ctrl_req.rdy;

  assign sysarr_ctrl_req.val          = xbar_sysarr_ctrl_req.val;
  assign sysarr_ctrl_req.msg.op       = t_op'(xbar_sysarr_ctrl_req.msg.op == MEMORY_MSG_WRITE ? MEM_MSG_WRITE :
                                               (xbar_sysarr_ctrl_req.msg.op == MEMORY_MSG_READ ? MEM_MSG_READ : 1'bx));
  assign sysarr_ctrl_req.msg.opaque   = xbar_sysarr_ctrl_req.msg.opaque;
  assign sysarr_ctrl_req.msg.origin   = xbar_sysarr_ctrl_req.msg.origin;
  assign sysarr_ctrl_req.msg.addr     = xbar_sysarr_ctrl_req.msg.addr;
  assign sysarr_ctrl_req.msg.strb     = xbar_sysarr_ctrl_req.msg.strb;
  assign sysarr_ctrl_req.msg.data     = xbar_sysarr_ctrl_req.msg.data;
  assign xbar_sysarr_ctrl_req.rdy     = sysarr_ctrl_req.rdy;

  assign peripheral_req.val           = xbar_peripheral_req.val;
  assign peripheral_req.msg.op        = t_op'(xbar_peripheral_req.msg.op == MEMORY_MSG_WRITE ? MEM_MSG_WRITE :
                                               (xbar_peripheral_req.msg.op == MEMORY_MSG_READ ? MEM_MSG_READ : 1'bx));
  assign peripheral_req.msg.opaque    = xbar_peripheral_req.msg.opaque;
  assign peripheral_req.msg.origin    = xbar_peripheral_req.msg.origin;
  assign peripheral_req.msg.addr      = xbar_peripheral_req.msg.addr;
  assign peripheral_req.msg.strb      = xbar_peripheral_req.msg.strb;
  assign peripheral_req.msg.data      = xbar_peripheral_req.msg.data;
  assign xbar_peripheral_req.rdy      = peripheral_req.rdy;

  // MemNet response interface bridges
  assign xbar_sram_resp.val           = sram_resp.val;
  assign xbar_sram_resp.msg.op        = mem_op'(sram_resp.msg.op == MEM_MSG_WRITE ? MEMORY_MSG_WRITE :
                                                 (sram_resp.msg.op == MEM_MSG_READ ? MEMORY_MSG_READ : MEMORY_MSG_X));
  assign xbar_sram_resp.msg.opaque    = sram_resp.msg.opaque;
  assign xbar_sram_resp.msg.origin    = sram_resp.msg.origin;
  assign xbar_sram_resp.msg.addr      = sram_resp.msg.addr;
  assign xbar_sram_resp.msg.strb      = sram_resp.msg.strb;
  assign xbar_sram_resp.msg.data      = sram_resp.msg.data;
  assign sram_resp.rdy                = xbar_sram_resp.rdy;

  assign xbar_mem_ctrl_resp.val       = mem_ctrl_resp.val;
  assign xbar_mem_ctrl_resp.msg.op    = mem_op'(mem_ctrl_resp.msg.op == MEM_MSG_WRITE ? MEMORY_MSG_WRITE :
                                                 (mem_ctrl_resp.msg.op == MEM_MSG_READ ? MEMORY_MSG_READ : MEMORY_MSG_X));
  assign xbar_mem_ctrl_resp.msg.opaque= mem_ctrl_resp.msg.opaque;
  assign xbar_mem_ctrl_resp.msg.origin= mem_ctrl_resp.msg.origin;
  assign xbar_mem_ctrl_resp.msg.addr  = mem_ctrl_resp.msg.addr;
  assign xbar_mem_ctrl_resp.msg.strb  = mem_ctrl_resp.msg.strb;
  assign xbar_mem_ctrl_resp.msg.data  = mem_ctrl_resp.msg.data;
  assign mem_ctrl_resp.rdy            = xbar_mem_ctrl_resp.rdy;

  assign xbar_cpu_ctrl_resp.val       = cpu_ctrl_resp.val;
  assign xbar_cpu_ctrl_resp.msg.op    = mem_op'(cpu_ctrl_resp.msg.op == MEM_MSG_WRITE ? MEMORY_MSG_WRITE :
                                                 (cpu_ctrl_resp.msg.op == MEM_MSG_READ ? MEMORY_MSG_READ : MEMORY_MSG_X));
  assign xbar_cpu_ctrl_resp.msg.opaque= cpu_ctrl_resp.msg.opaque;
  assign xbar_cpu_ctrl_resp.msg.origin= cpu_ctrl_resp.msg.origin;
  assign xbar_cpu_ctrl_resp.msg.addr  = cpu_ctrl_resp.msg.addr;
  assign xbar_cpu_ctrl_resp.msg.strb  = cpu_ctrl_resp.msg.strb;
  assign xbar_cpu_ctrl_resp.msg.data  = cpu_ctrl_resp.msg.data;
  assign cpu_ctrl_resp.rdy            = xbar_cpu_ctrl_resp.rdy;

  assign xbar_sysarr_ctrl_resp.val    = sysarr_ctrl_resp.val;
  assign xbar_sysarr_ctrl_resp.msg.op = mem_op'(sysarr_ctrl_resp.msg.op == MEM_MSG_WRITE ? MEMORY_MSG_WRITE :
                                                 (sysarr_ctrl_resp.msg.op == MEM_MSG_READ ? MEMORY_MSG_READ : MEMORY_MSG_X));
  assign xbar_sysarr_ctrl_resp.msg.opaque = sysarr_ctrl_resp.msg.opaque;
  assign xbar_sysarr_ctrl_resp.msg.origin = sysarr_ctrl_resp.msg.origin;
  assign xbar_sysarr_ctrl_resp.msg.addr   = sysarr_ctrl_resp.msg.addr;
  assign xbar_sysarr_ctrl_resp.msg.strb   = sysarr_ctrl_resp.msg.strb;
  assign xbar_sysarr_ctrl_resp.msg.data   = sysarr_ctrl_resp.msg.data;
  assign sysarr_ctrl_resp.rdy             = xbar_sysarr_ctrl_resp.rdy;

  assign xbar_peripheral_resp.val    = peripheral_resp.val;
  assign xbar_peripheral_resp.msg.op = mem_op'(peripheral_resp.msg.op == MEM_MSG_WRITE ? MEMORY_MSG_WRITE :
                                                (peripheral_resp.msg.op == MEM_MSG_READ ? MEMORY_MSG_READ : MEMORY_MSG_X));
  assign xbar_peripheral_resp.msg.opaque = peripheral_resp.msg.opaque;
  assign xbar_peripheral_resp.msg.origin = peripheral_resp.msg.origin;
  assign xbar_peripheral_resp.msg.addr   = peripheral_resp.msg.addr;
  assign xbar_peripheral_resp.msg.strb   = peripheral_resp.msg.strb;
  assign xbar_peripheral_resp.msg.data   = peripheral_resp.msg.data;
  assign peripheral_resp.rdy             = xbar_peripheral_resp.rdy;

  top_sp26_tapein1_MemXbar #(
    .p_opaq_bits (p_opaq_bits)
  ) xbar (
    .clk              (clk),
    .rst              (rst),
    // Servers
    .imem             (xbar_mem_intf[0]),
    .dmem             (xbar_mem_intf[1]),
    .spi              (xbar_spi_intf),
    .sysarr           (xbar_sysarr_intf),
    // Clients
    .memory_req       (xbar_sram_req),
    .memory_resp      (xbar_sram_resp),
    .memory_ctrl_req  (xbar_mem_ctrl_req),
    .memory_ctrl_resp (xbar_mem_ctrl_resp),
    .cpu_ctrl_req     (xbar_cpu_ctrl_req),
    .cpu_ctrl_resp    (xbar_cpu_ctrl_resp),
    .sysarr_ctrl_req  (xbar_sysarr_ctrl_req),
    .sysarr_ctrl_resp (xbar_sysarr_ctrl_resp),
    .peripheral_req   (xbar_peripheral_req),
    .peripheral_resp  (xbar_peripheral_resp)
  );

  SRAMMem #(
    .p_opaq_bits   (p_opaq_bits),
    .p_num_entries (p_num_entries)
  ) sram (
    .req  (sram_req),
    .resp (sram_resp),
    .*
  );

  FLPeripherals #(
    .p_send_intv_delay ( 1 ),
    .p_recv_intv_delay ( 1 ),
    .p_opaq_bits       (p_opaq_bits)
  ) peripherals (
    .req  (peripheral_req),
    .resp (peripheral_resp),
    .*
  );
  
  // disable spi and systolic array requests

  assign spi_intf.req_msg  = '0;
  assign spi_intf.req_val  = 1'b0;
  assign spi_intf.resp_rdy = 1'b1;

  assign sysarr_intf.req_msg  = '0;
  assign sysarr_intf.req_val  = 1'b0;
  assign sysarr_intf.resp_rdy = 1'b1;

  // disable memory mapped control reg for now

  assign mem_ctrl_resp.val = 1'b0;
  assign mem_ctrl_resp.msg = '0;

  assign cpu_ctrl_resp.val = 1'b0;
  assign cpu_ctrl_resp.msg = '0;

  assign sysarr_ctrl_resp.val = 1'b0;
  assign sysarr_ctrl_resp.msg = '0;

  //----------------------------------------------------------------------
  // Send data manually inside SRAM
  //----------------------------------------------------------------------

  function void init_mem(
    input bit [31:0] addr,
    input bit [31:0] data
  );
    sram.sram_minion.sram.sram.mem[addr[p_num_bits+1:2]] = data;
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

    trace = {trace, peripherals.trace( t.trace_level )};
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
  // Run the simulation
  //----------------------------------------------------------------------

  initial begin
    t.sim_begin();
    load_elf( t.elf_file );
  end

endmodule
