//========================================================================
// CircularPriorityEncoder.v
//========================================================================
// A priority encoder for circular buffers. Searching downward from
// ptr - 1 and wrapping around (ptr - 1, ptr - 2, ..., ptr), the first set
// bit of the input is selected. With ptr as a circular buffer's tail,
// this selects the youngest entry.
//
// All pointer arithmetic wraps modulo p_width, so p_width need not be a
// power of 2.

`ifndef HW_WRITEBACK_CIRCULAR_PRIORITY_ENCODER_V
`define HW_WRITEBACK_CIRCULAR_PRIORITY_ENCODER_V

module CircularPriorityEncoder #(
  parameter p_width    = 4,
  parameter p_ptr_bits = ( p_width > 1 ) ? $clog2( p_width ) : 1
)(
  input  logic    [p_width-1:0] in,
  input  logic [p_ptr_bits-1:0] ptr,
  output logic    [p_width-1:0] out
);

  generate
    //--------------------------------------------------------------------
    // Trivial case
    //--------------------------------------------------------------------

    if( p_width == 1 ) begin
      logic unused_ptr;
      assign unused_ptr = |ptr;
      assign out        = in;
    end

    //--------------------------------------------------------------------
    // General case
    //--------------------------------------------------------------------

    else begin
      always_comb begin
        logic found;
        int   idx;

        out   = '0;
        found = 1'b0;

        for( int k = 0; k < p_width; k = k + 1 ) begin
          // Index k positions below ptr - 1, wrapped modulo p_width
          idx = int'(ptr) - 1 - k;
          if( idx < 0 )
            idx = idx + p_width;

          if( !found && in[idx] ) begin
            out[idx] = 1'b1;
            found    = 1'b1;
          end
        end
      end
    end
  endgenerate

endmodule

`endif // HW_WRITEBACK_CIRCULAR_PRIORITY_ENCODER_V
