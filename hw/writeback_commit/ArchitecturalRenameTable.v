//========================================================================
// ArchitecturalRenameTable.v
//========================================================================

`ifndef HW_WRITEBACK_ARCHITECTURALRENAMETABLE_V
`define HW_WRITEBACK_ARCHITECTURALRENAMETABLE_V

`include "intf/CommitNotif.v"

module ArchitecturalRenameTable #(
  parameter p_num_phys_regs = 36,
  parameter p_phys_addr_bits = $clog2(p_num_phys_regs)
)(
  input logic clk,
  input logic rst,
  CommitNotif.sub commit,
  // Include this cycle's successful commit
  output logic [p_phys_addr_bits-1:0] recovery_map [31:1]
);
  logic [p_phys_addr_bits-1:0] architectural_rename_table [31:1];

  for( genvar i = 1; i < 32; i = i + 1 ) begin: ENTRY
    always_comb begin
      recovery_map[i] = architectural_rename_table[i];
      if( commit.val && commit.wen && commit.waddr == 5'(i) )
        recovery_map[i] = commit.preg;
    end

    always_ff @(posedge clk) begin
      if( rst )
        architectural_rename_table[i] <= p_phys_addr_bits'(i);
      else
        architectural_rename_table[i] <= recovery_map[i];
    end
  end
endmodule
`endif
