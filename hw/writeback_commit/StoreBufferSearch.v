//========================================================================
// StoreBufferSearch.v
//========================================================================
// Searches a circular buffer for a word address. For each of
// the 4 bytes of the word, it returns the youngest matching byte.

`ifndef HW_WRITEBACK_STORE_BUFFER_SEARCH_V
`define HW_WRITEBACK_STORE_BUFFER_SEARCH_V

`include "hw/writeback_commit/CircularPriorityEncoder.v"

module StoreBufferSearch #(
  parameter p_depth    = 4,
  parameter p_ptr_bits = ( p_depth > 1 ) ? $clog2( p_depth ) : 1
)(
  // Entries
  input  logic                  search_val [p_depth],
  input  logic           [31:2] addr       [p_depth],
  input  logic            [3:0] strb       [p_depth],
  input  logic           [31:0] data       [p_depth],
  input  logic [p_ptr_bits-1:0] tail,

  // Search
  input  logic           [31:2] search_addr,
  output logic            [3:0] hit,
  output logic           [31:0] search_data
);

  //----------------------------------------------------------------------
  // Address match (shared across lanes)
  //----------------------------------------------------------------------

  logic [p_depth-1:0] addr_match;

  genvar i, l;
  generate
    for( i = 0; i < p_depth; i = i + 1 ) begin: ADDR_MATCH
      assign addr_match[i] = search_val[i] & ( addr[i] == search_addr );
    end
  endgenerate

  //----------------------------------------------------------------------
  // Per-lane youngest select
  //----------------------------------------------------------------------

  generate
    for( l = 0; l < 4; l = l + 1 ) begin: LANE
      logic [p_depth-1:0] match;
      logic [p_depth-1:0] sel;

      for( i = 0; i < p_depth; i = i + 1 ) begin: LANE_MATCH
        assign match[i] = addr_match[i] & strb[i][l];
      end

      CircularPriorityEncoder #(
        .p_width    (p_depth),
        .p_ptr_bits (p_ptr_bits)
      ) youngest (
        .in  (match),
        .ptr (tail),
        .out (sel)
      );

      logic [7:0] lane_data;

      always_comb begin
        lane_data = 8'b0;
        for( int j = 0; j < p_depth; j = j + 1 ) begin
          if( sel[j] )
            lane_data = lane_data | data[j][8*l+7 : 8*l];
        end
      end

      assign hit[l]                = |match;
      assign search_data[8*l+7 : 8*l] = lane_data;
    end
  endgenerate

endmodule

`endif // HW_WRITEBACK_STORE_BUFFER_SEARCH_V
