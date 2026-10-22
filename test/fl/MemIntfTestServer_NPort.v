//========================================================================
// MemIntfTestServer_NPort.v
//========================================================================
// A FL model of a memory server with a parametrized number of ports, to
// use in testing and simulation. All ports share one memory
//
// Here, we also include support for our FL memory-mapped peripherals

`include "fl/fl_peripherals.v"
`include "hw/util/DelayStream.v"
`include "intf/MemIntf.v"
`include "types/MemMsg.v"

`ifndef TEST_FL_MEM_INTF_TEST_SERVER_N_PORT_V
`define TEST_FL_MEM_INTF_TEST_SERVER_N_PORT_V

module MemIntfTestServer_NPort #(
  parameter type t_req_msg  = `MEM_REQ ( 8 ),
  parameter type t_resp_msg = `MEM_RESP( 8 ),
  parameter p_opaq_bits     = 8,
  parameter p_num_ports     = 2,

  parameter p_send_intv_delay = 1,
  parameter p_recv_intv_delay = 1
)(
  input  logic clk,
  input  logic rst,

  MemIntf.server dut [p_num_ports]
);

  //----------------------------------------------------------------------
  // Store memory values in association array
  //----------------------------------------------------------------------

  logic [31:0] mem [logic [31:0]];

  always @( posedge clk ) begin
    if( rst )
      mem.delete();
  end

  function void init_mem(
    input logic [31:0] addr,
    input logic [31:0] data
  );
    mem[addr] = data;
  endfunction

  //----------------------------------------------------------------------
  // Keep track of cycles since reset
  //----------------------------------------------------------------------

  localparam CYCLE_COUNT_ADDR = 32'hFFFFFF00;

  logic [31:0] cycle_count;

  always_ff @( posedge clk ) begin
    if( rst )
      cycle_count <= '0;
    else
      cycle_count <= cycle_count + 1;
  end

  //----------------------------------------------------------------------
  // Execute a transaction
  //----------------------------------------------------------------------

  function automatic t_resp_msg transaction( input t_req_msg req );
    t_resp_msg   resp;
    logic [31:0] write_data;

    case( req.op )
      MEM_MSG_READ: begin
        if( try_fl_read(req.addr, resp.data) );
        else if( req.addr == CYCLE_COUNT_ADDR )
          resp.data = cycle_count;
        else if( mem.exists( req.addr ) == 1 )
          resp.data = mem[req.addr];
        else
          resp.data = 'x;
        resp.strb = req.strb;
      end
      MEM_MSG_WRITE: begin
        write_data = mem[req.addr];
        if( ( req.strb & 4'b0001 ) > 0 )
          write_data[7:0]   = req.data[7:0];
        if( ( req.strb & 4'b0010 ) > 0 )
          write_data[15:8]  = req.data[15:8];
        if( ( req.strb & 4'b0100 ) > 0 )
          write_data[23:16] = req.data[23:16];
        if( ( req.strb & 4'b1000 ) > 0 )
          write_data[31:24] = req.data[31:24];

        if( req.strb == 4'b1111 ) begin
          if( try_fl_write(req.addr, write_data) );
          else
            mem[req.addr] = write_data;
        end else begin
          mem[req.addr] = write_data;
        end
        resp.data = 'x;
        resp.strb = req.strb;
      end
      default: begin
        resp.data = 'x;
        resp.strb = req.strb;
      end
    endcase

    resp.op     = req.op;
    resp.addr   = req.addr;
    resp.opaque = req.opaque;

    return resp;
  endfunction

  //----------------------------------------------------------------------
  // Ports
  //----------------------------------------------------------------------
  // Each port has queues for sending and receiving memory messages, and
  // executes one transaction per cycle

  // Per-port copies of the interface signals, for linetracing
  logic      trace_req_xfer  [p_num_ports];
  t_req_msg  trace_req_msg   [p_num_ports];
  logic      trace_resp_xfer [p_num_ports];
  t_resp_msg trace_resp_msg  [p_num_ports];

  genvar i;
  generate
    for( i = 0; i < p_num_ports; i = i + 1 ) begin: PORT

      // verilator lint_off PINCONNECTEMPTY

      DelayStream #(
        .t_msg             (t_req_msg),
        .p_send_intv_delay (p_send_intv_delay)
      ) req_queue (
        .clk      (clk),
        .rst      (rst),

        .send_val (dut[i].req_val),
        .send_rdy (dut[i].req_rdy),
        .send_msg (dut[i].req_msg),

        .recv_val (),
        .recv_rdy (1'b0),
        .recv_msg ()
      );

      DelayStream #(
        .t_msg             (t_resp_msg),
        .p_recv_intv_delay (p_recv_intv_delay)
      ) resp_queue (
        .clk      (clk),
        .rst      (rst),

        .send_val (1'b0),
        .send_rdy (),
        .send_msg ('x),

        .recv_val (dut[i].resp_val),
        .recv_rdy (dut[i].resp_rdy),
        .recv_msg (dut[i].resp_msg)
      );

      // verilator lint_on PINCONNECTEMPTY

      // verilator lint_off BLKSEQ
      always @( posedge clk ) begin
        if( req_queue.num_msgs() > 0 )
          resp_queue.enqueue( transaction( req_queue.dequeue() ) );
      end
      // verilator lint_on BLKSEQ

      assign trace_req_xfer[i]  = dut[i].req_val & dut[i].req_rdy;
      assign trace_req_msg[i]   = dut[i].req_msg;
      assign trace_resp_xfer[i] = dut[i].resp_val & dut[i].resp_rdy;
      assign trace_resp_msg[i]  = dut[i].resp_msg;

    end
  endgenerate

  //----------------------------------------------------------------------
  // Linetracing
  //----------------------------------------------------------------------

  function int ceil_div_4( int val );
    return (val / 4) + ((val % 4) > 0 ? 1 : 0);
  endfunction

  function string op_str( t_op op );
    case( op )
      MEM_MSG_READ:  return "rd";
      MEM_MSG_WRITE: return "wr";
      default:       return "??";
    endcase
  endfunction

  function string trace(int trace_level);
    string req_linetrace, resp_linetrace;
    int str_len;

    str_len = 2 + 1 +                       // op
              ceil_div_4(p_opaq_bits) + 1 + // opaque
              8                       + 1 + // addr
              8;                            // data

    trace = "";

    for( int p = 0; p < p_num_ports; p = p + 1 ) begin
      if( trace_req_xfer[p] ) begin
        req_linetrace = op_str( trace_req_msg[p].op );
        if( trace_level > 0 )
          req_linetrace = {req_linetrace, ":", $sformatf("%h:%h:%h",
                           trace_req_msg[p].opaque, trace_req_msg[p].addr,
                           trace_req_msg[p].data)};
      end else begin
        if( trace_level > 0 )
          req_linetrace = {str_len{" "}};
        else
          req_linetrace = {2{" "}};
      end

      if( trace_resp_xfer[p] ) begin
        resp_linetrace = op_str( trace_resp_msg[p].op );
        if( trace_level > 0 )
          resp_linetrace = {resp_linetrace, ":", $sformatf("%h:%h:%h",
                            trace_resp_msg[p].opaque, trace_resp_msg[p].addr,
                            trace_resp_msg[p].data)};
      end else begin
        if( trace_level > 0 )
          resp_linetrace = {str_len{" "}};
        else
          resp_linetrace = {2{" "}};
      end

      if( p == 0 )
        trace = $sformatf("%s > %s", req_linetrace, resp_linetrace);
      else
        trace = {trace, $sformatf(" - %s > %s", req_linetrace, resp_linetrace)};
    end
  endfunction

endmodule

`endif // TEST_FL_MEM_INTF_TEST_SERVER_N_PORT_V
