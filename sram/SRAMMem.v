`ifndef SRAM_SRAMMEM_V
`define SRAM_SRAMMEM_V

`include "fpga/net/MemNetReq.v"
`include "fpga/net/MemNetResp.v"

// not sure if this path resolves...
`include "ip/sram/rtl/sram_minion.sv"
`include "ip/sram/rtl/mem-msgs.sv"

module SRAMMem #(
  parameter p_opaq_bits = 8
)(
  input  logic clk,
  input  logic rst,

  MemNetReq.server  req,
  MemNetResp.server resp
);

  mem_resp_4B_t minion_reqstream_msg;
  mem_req_4B_t  minion_respstream_msg;

  sram_SRAMMinion sram_minion (
    .clk        (clk),
    .reset      (rst),

    .minion_reqstream_val(req.val),
    .minion_reqstream_rdy(req.rdy),
    .minion_reqstream_msg(minion_reqstream_msg),

    .minion_respstream_val(resp.val),
    .minion_respstream_rdy(resp.rdy),
    .minion_respstream_msg(minion_respstream_msg)
  );

  // Convert from MemNetReq to minion_reqstream_msg
  assign minion_reqstream_msg.type_ = req.msg.op;
  assign minion_reqstream_msg.opaque = req.msg.opaque;
  assign minion_reqstream_msg.addr  = req.msg.addr;
  assign minion_reqstream_msg.strb  = req.msg.strb;
  assign minion_reqstream_msg.data  = req.msg.data;

  // Convert from minion_respstream_msg to MemNetResp
  assign resp.msg.op      = minion_respstream_msg.type_;
  assign resp.msg.opaque  = minion_respstream_msg.opaque;
  assign resp.msg.addr    = minion_respstream_msg.addr;
  assign resp.msg.strb    = minion_respstream_msg.strb;
  assign resp.msg.data    = minion_respstream_msg.data;

endmodule

`endif