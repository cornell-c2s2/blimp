//========================================================================
// FLCSRfile.h
//========================================================================
// Machine-mode CSR state and access rules for the functional-level model.

#ifndef FL_CSRFILE_H
#define FL_CSRFILE_H

#include <cstdint>
#include <unordered_map>

namespace CSRAddr {
  constexpr uint32_t MSTATUS  = 0x300; // Includes MIE (global interrupt enable), MPIE (previous enable),
                                      // and MPP (previous privilege mode).
  constexpr uint32_t MIE      = 0x304; // Enables individual machine interrupt sources.
  constexpr uint32_t MTVEC    = 0x305; // Trap-handler address; this model uses Direct mode.
  constexpr uint32_t MSCRATCH = 0x340; // Software scratch storage for trap handlers.
  constexpr uint32_t MEPC     = 0x341; // Saved instruction address for trap return.
  constexpr uint32_t MCAUSE   = 0x342; // Trap cause, including whether it is an interrupt.
  constexpr uint32_t MTVAL    = 0x343; // Additional trap information, such as illegal instruction bits.
  constexpr uint32_t MIP      = 0x344; // Pending interrupts; always reads zero in this model.
}

class FLCSRfile {
  public:
    void reset();
    uint32_t read(uint32_t addr) const;
    bool contains( uint32_t addr ) const;
    void write( uint32_t addr, uint32_t value );
    uint32_t enter_trap(uint32_t pc, uint32_t cause, uint32_t tval ); // Saves trap state and returns the handler address from mtvec.
    uint32_t return_from_trap(); // Restores interrupt state and returns mepc.
  private:

    std::unordered_map<uint32_t, uint32_t> regs = {
      { CSRAddr::MSTATUS,  0x1800 },
      { CSRAddr::MIE,      0 },
      { CSRAddr::MTVEC,    0 },
      { CSRAddr::MSCRATCH, 0 },
      { CSRAddr::MEPC,     0 },
      { CSRAddr::MCAUSE,   0 },
      { CSRAddr::MTVAL,    0 },
      { CSRAddr::MIP,      0 }
    };

};

#endif  // FL_CSRFILE_H
