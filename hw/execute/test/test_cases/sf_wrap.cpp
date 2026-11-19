#include "softfloat.h"

unsigned int sf_fdiv(unsigned int a, unsigned int b) {
  float32_t fa, fb, fr;
  fa.v = a;
  fb.v = b;
  softfloat_roundingMode  = softfloat_round_near_even;
  softfloat_exceptionFlags = 0;
  fr = f32_div(fa, fb);
  return fr.v;
}
