//========================================================================
// MemArbiter2.v
//========================================================================
// Simple 2-input memory arbiter for BLIMP
//
// - Fixed priority: mem1 (FP) > mem0 (INT)
// - Tracks owner of outstanding request
// - Routes response back to correct unit
//
// Assumes at most one outstanding shared-memory request at a time.
//
// Author: Sumaia Jewena
//========================================================================

`ifndef HW_COMMON_MEMARBITER2_V
`define HW_COMMON_MEMARBITER2_V

`include "intf/MemIntf.v"

module MemArbiter2 (
  input  logic clk,
  input  logic rst,

  // Two memory clients, viewed from the arbiter as servers
  MemIntf.server mem0, // INT LSU
  MemIntf.server mem1, // FP LSU

  // Shared memory, viewed from the arbiter as a client
  MemIntf.client mem_out
);

  typedef enum logic {
    OWNER_MEM0 = 1'b0,
    OWNER_MEM1 = 1'b1
  } owner_t;

  owner_t owner_reg, owner_next;

  logic owner_valid_reg, owner_valid_next;
  logic req_fire, resp_fire;

  assign req_fire  = mem_out.req_val  & mem_out.req_rdy;
  assign resp_fire = mem_out.resp_val & mem_out.resp_rdy;

  always_ff @(posedge clk) begin
    if (rst) begin
      owner_reg       <= OWNER_MEM0;
      owner_valid_reg <= 1'b0;
    end
    else begin
      owner_reg       <= owner_next;
      owner_valid_reg <= owner_valid_next;
    end
  end

  always_comb begin
    owner_next       = owner_reg;
    owner_valid_next = owner_valid_reg;

    if (req_fire) begin
      if (mem1.req_val)
        owner_next = OWNER_MEM1;
      else
        owner_next = OWNER_MEM0;

      owner_valid_next = 1'b1;
    end

    if (resp_fire)
      owner_valid_next = 1'b0;
  end

  // Request mux: mem1 has priority
  always_comb begin
    mem_out.req_val = 1'b0;
    mem_out.req_msg = '0;

    mem0.req_rdy = 1'b0;
    mem1.req_rdy = 1'b0;

    if (mem1.req_val) begin
      mem_out.req_val = mem1.req_val;
      mem_out.req_msg = mem1.req_msg;
      mem1.req_rdy    = mem_out.req_rdy;
    end
    else begin
      mem_out.req_val = mem0.req_val;
      mem_out.req_msg = mem0.req_msg;
      mem0.req_rdy    = mem_out.req_rdy;
    end
  end

  // Response routing
  assign mem0.resp_val = owner_valid_reg & (owner_reg == OWNER_MEM0) & mem_out.resp_val;
  assign mem1.resp_val = owner_valid_reg & (owner_reg == OWNER_MEM1) & mem_out.resp_val;

  assign mem0.resp_msg = mem_out.resp_msg;
  assign mem1.resp_msg = mem_out.resp_msg;

  assign mem_out.resp_rdy =
    owner_valid_reg
      ? ((owner_reg == OWNER_MEM0) ? mem0.resp_rdy
                                   : mem1.resp_rdy)
      : 1'b0;

endmodule

`endif // HW_COMMON_MEMARBITER2_V
