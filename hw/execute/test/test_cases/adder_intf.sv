interface adder_intf(input logic clk);
  logic                        reset;
  // logic internal_ground;
  // logic internal_sticky;
  // logic internal_roundb;
  // logic internal_last_bit_mantissa;
  // logic internal_denorm_one;
  // logic internal_denorm_two;
  // logic internal_nan_one;
  // logic internal_nan_two;
  // logic sign_bit_one;
  // logic sign_bit_two;
  logic [31:0] operand_one;
  logic [31:0] operand_two;

endinterface