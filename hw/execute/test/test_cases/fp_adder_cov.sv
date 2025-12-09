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

  internal_ground : coverpoint vif.internal_ground
  {
      bins zero = { 0 };
      bins one = { 1 };
  }

  internal_sticky : coverpoint vif.internal_sticky
  {
      bins zero = { 0 };
      bins one = { 1 };
  }

  internal_roundb : coverpoint vif.internal_roundb
  {
      bins zero = { 0 };
      bins one = { 1 };
  }

  internal_last_bit_mantissa : coverpoint vif.internal_last_bit_mantissa
  {
      bins zero = { 0 };
      bins one = { 1 };
  }

  internal_denorm_one : coverpoint vif.internal_denorm_one
  {
      bins not_denorm = { 0 };
      bins is_denorm = { 1 };
  }

  internal_denorm_two : coverpoint vif.internal_denorm_two
  {
      bins not_denorm = { 0 };
      bins is_denorm = { 1 };
  }

  internal_nan_one : coverpoint vif.internal_nan_one
  {
      bins not_nan = { 0 };
      bins is_nan = { 1 };
  }

  internal_nan_two : coverpoint vif.internal_nan_two
  {
      bins not_nan = { 0 };
      bins is_nan = { 1 };
  }

  internal_signed_exponent_one : coverpoint vif.signed_exponent_one
  {
      bins zero        = {9'b0};                 // all zeros
      bins pos_small   = {[9'b000000001:9'b000001111]}; // magnitude 1–15
      bins pos_medium  = {[9'b000010000:9'b011111111]}; // magnitude 16–255
      bins neg_small   = {[9'b100000001:9'b100001111]}; // magnitude 1–15
      bins neg_medium  = {[9'b100010000:9'b111111111]}; // magnitude 16–255
  }

  internal_signed_exponent_two : coverpoint vif.signed_exponent_two
  {
      bins zero        = {9'b0};                 // all zeros
      bins pos_small   = {[9'b000000001:9'b000001111]}; // magnitude 1–15
      bins pos_medium  = {[9'b000010000:9'b011111111]}; // magnitude 16–255
      bins neg_small   = {[9'b100000001:9'b100001111]}; // magnitude 1–15
      bins neg_medium  = {[9'b100010000:9'b111111111]}; // magnitude 16–255
  }

  // Crosses must match coverpoint labels and end with semicolon
  mantissa_rounding : cross internal_last_bit_mantissa, internal_ground; // for rounding
  grs_combs: cross internal_ground, internal_roundb, internal_sticky; // all GRS combinations
  exponent_cross : cross internal_signed_exponent_one, internal_signed_exponent_two; // exponent difference checks
  subnormal_cross : cross internal_denorm_one, internal_denorm_two; // subnormal combinations

  
  endgroup

  function new(virtual adder_intf vif);
    this.vif = vif;
    cg = new; //create new instance of class
  endfunction


endclass
`endif