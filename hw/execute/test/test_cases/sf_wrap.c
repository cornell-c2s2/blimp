#include <cstdint>

extern "C" {
#include "softfloat.h"      // C header, so no C++ name mangling
}

extern "C" uint32_t sf_fdiv(uint32_t a, uint32_t b) {
  float32_t fa, fb;
  fa.v = a;
  fb.v = b;
  return f32_div(fa, fb).v;
}