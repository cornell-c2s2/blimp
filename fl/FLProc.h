//========================================================================
// FLProc.h
//========================================================================
// Declarations for our functional-level processor

#ifndef FL_PROC_H
#define FL_PROC_H

#include "fl/FLInst.h"
#include "fl/FLMem.h"
#include "fl/FLRegfile.h"
#include "fl/FLTrace.h"
#include "fl/peripherals/FLExit.h"
#include "fl/peripherals/FLTerminal.h"
#include <cstdint>
#include <map>

class FLProc {
  //----------------------------------------------------------------------
  // Public accessor functions
  //----------------------------------------------------------------------
 public:
  FLProc();

  // Reset state
  void reset();

  // Initialize memory
  void init( uint32_t addr, uint32_t inst );
  void init( uint32_t addr, std::string assembly );

  // Step one instruction in execution
  FLTrace step();

  //----------------------------------------------------------------------
  // Protected attrributes
  //----------------------------------------------------------------------
 protected:
  uint32_t  pc;
  FLRegfile regs;
  FLMem     mem;

  // Peripherals
  FLExit     exit;
  FLTerminal terminal;

  // Machine-mode-only CSRs: MPP is fixed to M, mtvec uses Direct mode.
  struct MachineCsrs {
    uint32_t mtvec    = 0;
    uint32_t mstatus  = 0x1800;
    uint32_t mie      = 0;
    uint32_t mcause   = 0;
    uint32_t mepc     = 0;
    uint32_t mtval    = 0;
    uint32_t mscratch = 0;
  } csrs;

  bool     has_csr( uint32_t addr ) const;
  uint32_t read_csr( uint32_t addr );
  void     write_csr( uint32_t addr, uint32_t val );
  FLTrace  take_trap( uint32_t cause, uint32_t tval = 0 );
};

#endif  // FL_PROC_H
