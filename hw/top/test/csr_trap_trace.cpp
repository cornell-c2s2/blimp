//========================================================================
// csr_trap_trace.cpp
//========================================================================
// Test-only access to trap events, which FLTrace::vrep cannot represent.
// Use the same ISS instance as fl_reset/fl_init/fl_trace; do not emulate
// traps or turn an unsupported instruction into a successful trace.

#include "fl/FLProc.h"
#include <exception>
#include <iostream>

extern FLProc proc;

extern "C" bool fl_check_trap( unsigned int pc, unsigned int cause )
{
  try {
    FLTrace actual = proc.step();
    FLTrace expected( pc, true, cause );
    if ( actual == expected )
      return true;
    std::cerr << "Expected " << expected << ", got " << actual << '\n';
  } catch ( const std::exception& error ) {
    std::cerr << "ISS trap step failed: " << error.what() << '\n';
  }
  return false;
}
