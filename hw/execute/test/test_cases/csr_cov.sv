`ifndef VERILATOR

class csr_cvg;
    virtual CSRIntf vif;

    covergroup cg with function sample(
      input logic [2:0]  cmd_i,
      input logic [11:0] addr_i,
      input logic [31:0] wdata_i,
      input logic [31:0] rdata_i,
      input logic        waddr_is_x0_i,
      input logic        wen_i
    );

    option.per_instance = 1;

    // Command semantics for this unit: only CSRRW/CSRRS/CSRRC are legal.
    cmd : coverpoint cmd_i {
      bins csrrw = {3'b001};
      bins csrrs = {3'b010};
      bins csrrc = {3'b011};
      illegal_bins non_csr_cmd = default;
    }

    // Addresses of interest (per CSRFile.v: 0x001, 0x002, 0x003)
    addr : coverpoint addr_i {
      bins fflags = {12'h001};
      bins frm    = {12'h002};
      bins fcsr   = {12'h003};
      bins other  = default;
    }

    // Data patterns on write data
    wdata_zero: coverpoint (wdata_i == 32'h0000_0000) {
      bins yes = {1};
      bins no  = {0};
    }

    wdata_ones: coverpoint (wdata_i == 32'hFFFF_FFFF) {
      bins yes = {1};
      bins no  = {0};
    }

    // Read data patterns that are reachable for implemented CSR widths.
    rdata_zero: coverpoint (rdata_i == 32'h0000_0000) {
      bins yes = {1};
      bins no  = {0};
    }

    rdata_fflags_max: coverpoint ((addr_i == 12'h001) && (rdata_i == 32'h0000_001F)) {
      bins hit = {1};
    }

    rdata_frm_max: coverpoint ((addr_i == 12'h002) && (rdata_i == 32'h0000_0007)) {
      bins hit = {1};
    }

    rdata_fcsr_max: coverpoint ((addr_i == 12'h003) && (rdata_i == 32'h0000_00FF)) {
      bins hit = {1};
    }

    waddr_x0: coverpoint waddr_is_x0_i {
      bins x0  = {1};
      bins nx0 = {0};
    }

    wen_cov: coverpoint wen_i {
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

    function new(virtual CSRIntf vif);
        this.vif = vif;
        cg = new();
    endfunction

    task sample(
      input logic [2:0]  cmd,
      input logic [11:0] addr,
      input logic [31:0] wdata,
      input logic [31:0] rdata,
      input logic [4:0]  waddr,
      input logic        wen
    );
      cg.sample(cmd, addr, wdata, rdata, (waddr == 5'd0), wen);
    endtask

endclass
`endif
