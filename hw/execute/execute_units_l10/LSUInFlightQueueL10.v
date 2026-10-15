//========================================================================
// LSUInFlightQueueL10.v
//========================================================================
// FIFO bookkeeping for LSU operations. Squash marks entries killed but
// preserves their order so outstanding memory responses can be drained.
// Like Fifo, depth must be a power of two. The caller must not pop an
// empty queue or push a full queue (except while also popping).

`ifndef HW_EXECUTE_LSUINFLIGHTQUEUEL10_V
`define HW_EXECUTE_LSUINFLIGHTQUEUEL10_V

`include "hw/util/SeqAge.v"
`include "intf/CommitNotif.v"
`include "intf/SquashNotif.v"

module LSUInFlightQueueL10 #(
  parameter p_entry_bits = 32,
  parameter p_depth      = 32
)(
  input  logic clk,
  input  logic rst,

  CommitNotif.sub commit,
  SquashNotif.sub squash,

  input  logic push,
  input  logic pop,
  output logic empty,
  output logic full,
  output logic rdata_killed,

  input  logic [p_entry_bits-1:0] wdata,
  input  logic [commit.p_seq_num_bits-1:0] wseq_num,
  output logic [p_entry_bits-1:0] rdata
);

  localparam p_seq_num_bits = commit.p_seq_num_bits;
  localparam p_addr_bits = $clog2(p_depth);

  //----------------------------------------------------------------------
  // Create our pointers
  //----------------------------------------------------------------------

  logic [p_addr_bits:0] rptr, wptr;

  always_ff @( posedge clk ) begin
    if( rst ) begin
      rptr <= '0;
      wptr <= '0;
    end else begin
      if( push ) wptr <= wptr - 1'b1;
      if( pop  ) rptr <= rptr - 1'b1;
    end
  end

  assign empty = (wptr == rptr);
  generate
    if( p_depth == 1 )
      assign full = (wptr != rptr);
    else
      assign full = (wptr[p_addr_bits-1:0] == rptr[p_addr_bits-1:0])
                  & (wptr[p_addr_bits] != rptr[p_addr_bits]);
  endgenerate

  //----------------------------------------------------------------------
  // Squashing
  //----------------------------------------------------------------------

  SeqAge seq_age ( .* );

  //----------------------------------------------------------------------
  // Data and per-entry metadata
  //----------------------------------------------------------------------
  // Payload ports are bit vectors; kill state is carried separately.

  generate
    if( p_depth == 1 ) begin: SINGLE_SLOT
      logic [p_entry_bits-1:0] data_arr;
      logic [p_seq_num_bits-1:0] seq_num_arr;
      logic killed;

      always_ff @( posedge clk ) begin
        if( rst ) begin
          data_arr <= '0;
          seq_num_arr <= '0;
          killed <= 1'b0;
        end else if( push ) begin
          data_arr <= wdata;
          seq_num_arr <= wseq_num;
          killed <= squash.val &
                    seq_age.is_older(squash.seq_num, wseq_num);
        end else if( !empty && squash.val &&
                     seq_age.is_older(squash.seq_num, seq_num_arr) )
          killed <= 1'b1;
      end

      assign rdata = data_arr;
      // Include this cycle's squash, even if the entry is popping now.
      assign rdata_killed = !empty & (killed |
        (squash.val & seq_age.is_older(squash.seq_num, seq_num_arr)));

    end else begin: MULTIPLE_SLOTS
      logic [p_entry_bits-1:0] data_arr [p_depth-1:0];
      logic [p_seq_num_bits-1:0] seq_num_arr [p_depth-1:0];
      logic killed [p_depth-1:0];
      logic occupied [p_depth-1:0];

      always_ff @( posedge clk ) begin
        if( rst ) begin
          data_arr <= '{default: '0};
          seq_num_arr <= '{default: '0};
          killed <= '{default: 1'b0};
          occupied <= '{default: 1'b0};
        end else begin
          for( int i = 0; i < p_depth; i = i + 1 ) begin
            // A replacement push wins over pop for the same slot.
            if( push && wptr[p_addr_bits-1:0] == p_addr_bits'(i) ) begin
              data_arr[i] <= wdata;
              seq_num_arr[i] <= wseq_num;
              occupied[i] <= 1'b1;
              killed[i] <= squash.val &
                           seq_age.is_older(squash.seq_num, wseq_num);
            end else begin
              if( pop && rptr[p_addr_bits-1:0] == p_addr_bits'(i) )
                occupied[i] <= 1'b0;
              // Sticky until this slot is reused, independent of pushes
              // to other slots and of later squash pulses.
              if( occupied[i] && squash.val &&
                  seq_age.is_older(squash.seq_num, seq_num_arr[i]) )
                killed[i] <= 1'b1;
            end
          end
        end
      end

      assign rdata = data_arr[rptr[p_addr_bits-1:0]];
      assign rdata_killed = !empty & (killed[rptr[p_addr_bits-1:0]] |
        (squash.val & seq_age.is_older(
          squash.seq_num, seq_num_arr[rptr[p_addr_bits-1:0]])));
    end
  endgenerate

endmodule

`endif // HW_EXECUTE_LSUINFLIGHTQUEUEL10_V
