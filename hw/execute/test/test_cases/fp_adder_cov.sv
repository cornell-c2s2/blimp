// class adder_trans;

// covergroup AdderCovGrp;
//   coverpoint ground {
//     bins round_down = {0};
//     bins round_up = {1};
//     bins reserve = default;
//   }

//   coverpoint bttm_bit {
//     bins round_down = {0};
//     bins round_up = {1};
//     bins reserve = default;
//   }

//   coverpoint 

//   cross ground, 
// endgroup

// endclass


`ifndef VERILATOR

// `include "adder_intf.sv"
class adder_cvg;

  virtual adder_intf vif;

  covergroup cg @(posedge vif.clk);
  coverpoint vif.operand_one;
  coverpoint vif.operand_two;

  // coverpoint  {
  //   bins round_down = {0};
  //   bins round_up = {1};
  //   bins reserve = default;
  // }
  endgroup


  function new(virtual adder_intf vif);
    this.vif = vif;
    cg = new; //create new instance of class
  endfunction

  // function void sample_cvg();
  //   cg.sample();
  // endfunction

endclass
`endif