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


class adder_cvg;

  virtual adder_intf vif;

  covergroup cg;
  coverpoint ground {
    bins round_down = {0};
    bins round_up = {1};
    bins reserve = default;
  }

  coverpoint bttm_bit {
    bins round_down = {0};
    bins round_up = {1};
    bins reserve = default;
  }
  endgroup

  function new(virtual sram_minion_if vif);
    this.vif = vif;
    cg = new()
  endfunction

  function void sample_cvg();
    cg.sample();
  endfunction

endclass