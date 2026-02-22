`ifndef VERILATOR

class csr_cvg;
    virtual CSRIntf vif;

    covergroup cg;

    // Handshake gating
    val : coverpoint vif.val {
      bins inactive = {0};
      bins active   = {1};
    }

    rdy : coverpoint vif.rdy {
      bins not_ready = {0};
      bins ready     = {1};
      ignore_bins unreachable_not_ready = {0};
    }

    x_handshake: cross val, rdy {
      ignore_bins not_ready = binsof(rdy.not_ready);
    }

    // Command semantics
    cmd : coverpoint vif.cmd {
      bins read   = {3'b000};
      bins csrrw  = {3'b001};
      bins csrrs  = {3'b010};
      bins csrrc  = {3'b011};
      bins others = default;
    }

    // Addresses of interest (per CSRFile.v: 0x001, 0x002, 0x003)
    addr : coverpoint vif.addr {
      bins fflags = {12'h001};
      bins frm    = {12'h002};
      bins fcsr   = {12'h003};
      bins other  = default;
    }

    // Data patterns on write data
    wdata_zero: coverpoint (vif.wdata == 32'h0000_0000) {
      bins yes = {1};
      bins no  = {0};
    }

    wdata_ones: coverpoint (vif.wdata == 32'hFFFF_FFFF) {
      bins yes = {1};
      bins no  = {0};
    }

    // Data patterns on read data
    rdata_zero: coverpoint (vif.rdata == 32'h0000_0000) {
      bins yes = {1};
      bins no  = {0};
    }

    rdata_ones: coverpoint (vif.rdata == 32'hFFFF_FFFF) {
      bins yes = {1};
      bins no  = {0};
    }

    // Derived coverage points (passed as parameters to sample method)
    waddr_x0: coverpoint waddr_is_x0_val {
      bins x0  = {1};
      bins nx0 = {0};
    }

    wen_cov: coverpoint wen_val {
      bins no_write = {0};
      bins write    = {1};
    }

    // Key behavioral crosses
    x_cmd_addr: cross cmd, addr;
    x_cmd_x0:   cross cmd, waddr_x0;

    x_waddr_wen: cross waddr_x0, wen_cov {
      ignore_bins impossible_no_write_nx0 =
        binsof(waddr_x0.nx0) && binsof(wen_cov.no_write);
      ignore_bins impossible_write_x0 =
        binsof(waddr_x0.x0) && binsof(wen_cov.write);
    }

    x_cmd_wdata_zero: cross cmd, wdata_zero;
    x_cmd_wdata_ones: cross cmd, wdata_ones;
    x_cmd_rdata_zero: cross cmd, rdata_zero;
    x_addr_waddr_x0:  cross addr, waddr_x0;
    x_cmd_wen:        cross cmd, wen_cov;

    endgroup

    // Internal state for derived coverpoints
    logic waddr_is_x0_val = 0;
    logic wen_val = 0;

    function new(virtual CSRIntf vif);
        this.vif = vif;
        cg = new();
    endfunction

    task sample(input logic [4:0] waddr = 5'hx, input logic wen = 1'bx);
        // Compute derived values
        waddr_is_x0_val = (waddr == 5'd0);
        wen_val = wen;
        
        cg.sample();
    endtask

endclass
`endif
