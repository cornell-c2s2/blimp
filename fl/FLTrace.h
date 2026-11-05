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
  static constexpr uint32_t CSR_CMD_NONE  = 0;
  static constexpr uint32_t CSR_CMD_WRITE = 1;
  static constexpr uint32_t CSR_CMD_SET   = 2;
  static constexpr uint32_t CSR_CMD_CLEAR = 3;
  static constexpr uint32_t CSR_CMD_MRET  = 4;
  // Constructors
  FLTrace( uint32_t pc, uint32_t waddr, uint32_t wdata, bool wen );
  FLTrace( uint32_t *vstruct );
  // Trap events have no register writeback.
  FLTrace( uint32_t pc, bool trap, uint32_t cause );

  void set_trap_value( uint32_t value );
  void set_redirect( uint32_t target );
  void set_csr_action( uint32_t cmd, uint32_t addr, uint32_t wdata );

  // Equality for comparing traces
  bool operator==( const FLTrace &other ) const;
  bool operator!=( const FLTrace &other ) const;

  // Trap fields (normal retirements use false/zero).
  bool     trap  = false;
  uint32_t cause = 0;
  uint32_t tval = 0;
  bool redirect_valid = false;
  uint32_t redirect_pc = 0;
  bool csr_action_valid = false;
  uint32_t csr_cmd = 0;
  uint32_t csr_addr = 0;
  uint32_t csr_wdata = 0;

  // String representation for stream output
  std::string          str() const;
  friend std::ostream &operator<<( std::ostream  &out,
                                   const FLTrace &trace );

  // Legacy three-word retirement-only Verilog representation.
  // Throws for traps, which this format cannot represent.
  void vrep( uint32_t *vstruct );
  void arch_vrep( uint32_t *vstruct ) const;

  static constexpr unsigned ARCH_WORDS = 5;

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
