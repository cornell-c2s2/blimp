`ifndef VERILATOR

class csr_cvg;
    virtual CSRIntf vif;
    logic clk;

    covergroup cg @(posedge clk);

    // The vif has addr, wdata, rdata, cmd

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
    endgroup

    function new(virtual CSRIntf vif, input logic clk);
        this.vif = vif;
        this.clk = clk;
        cg = new;
    endfunction

endclass
`endif
