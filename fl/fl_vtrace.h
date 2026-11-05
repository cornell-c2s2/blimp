//========================================================================
// fl_vtrace.h
//========================================================================
// A standalone functional-level tracer for SystemVerilog testbenches

#ifndef FL_FL_VTRACE_H
#define FL_FL_VTRACE_H

#include <cstdint>

extern "C" void        fl_reset();
extern "C" void        fl_init( uint32_t* addr, uint32_t* binary );
extern "C" bool        fl_trace( uint32_t* trace );
extern "C" bool        fl_arch_trace( uint32_t* trace );
extern "C" const char* fl_trace_str( uint32_t* trace );

#endif  // FL_FL_VTRACE_H
