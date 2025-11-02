`ifndef SRAM_SRAMMEM_V
`define SRAM_SRAMMEM_V

`include "fpga/net/MemNetReq.v"
`include "fpga/net/MemNetResp.v"

// not sure if this path resolves...
`include "ip/sram/rtl/sram_minion.sv"

module SRAMMem #(
  parameter p_opaq_bits = 8
)(
  input  logic clk,
  input  logic rst,

  MemNetReq.server  req,
  MemNetResp.server resp
);

  sram_SRAMMinion sram_minion (
    .clk        (clk),
    .reset      (rst),

    .minion_reqstream_val(req.val),
    .minion_reqstream_rdy(req.rdy),
    .minion_reqstream_msg(req.msg),

    .minion_respstream_val(resp.val),
    .minion_respstream_rdy(resp.rdy),
    .minion_respstream_msg(resp.msg)
  );

endmodule

`endif