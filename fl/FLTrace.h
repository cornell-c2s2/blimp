//========================================================================
// FLTrace.h
//========================================================================
// Declarations for our processor trace

#ifndef FL_TRACE_H
#define FL_TRACE_H

#include <cstdint>
#include <iostream>
#include <string>

class FLTrace {
  //----------------------------------------------------------------------
  // Public accessor functions
  //----------------------------------------------------------------------
 public:
  // Constructors
  FLTrace( uint32_t pc, uint32_t waddr, uint32_t wdata, bool wen );
  FLTrace( uint32_t *vstruct );
  // Trap events have no register writeback.
  FLTrace( uint32_t pc, bool trap, uint32_t cause );

  // Equality for comparing traces
  bool operator==( const FLTrace &other ) const;
  bool operator!=( const FLTrace &other ) const;

  // Trap fields (normal retirements use false/zero).
  bool     trap  = false;
  uint32_t cause = 0;

  // String representation for stream output
  std::string          str() const;
  friend std::ostream &operator<<( std::ostream  &out,
                                   const FLTrace &trace );

  // Legacy three-word retirement-only Verilog representation.
  // Throws for traps, which this format cannot represent.
  void vrep( uint32_t *vstruct );

  //----------------------------------------------------------------------
  // Protected attrributes
  //----------------------------------------------------------------------
 protected:
  uint32_t pc;
  uint32_t waddr;
  uint32_t wdata;
  bool     wen;
};

#endif  // FL_TRACE_H
