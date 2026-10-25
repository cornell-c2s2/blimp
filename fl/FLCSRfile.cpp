//========================================================================
// FLCSRfile.cpp
//========================================================================
// Definitions for the functional-level machine-mode CSR file.

#include "fl/FLCSRfile.h"

//------------------------------------------------------------------------
// Reset
//------------------------------------------------------------------------

void FLCSRfile::reset()
{
  regs = FLCSRfile{}.regs;
}

//------------------------------------------------------------------------
// Read
//------------------------------------------------------------------------

uint32_t FLCSRfile::read( uint32_t addr ) const
{
    auto it = regs.find(addr);
    return it != regs.end() ? it->second : 0; // getting the value in the unordered_map
}

//------------------------------------------------------------------------
// Address support
//------------------------------------------------------------------------

bool FLCSRfile::contains( uint32_t addr ) const
{
    return regs.find(addr) != regs.end();
}

//------------------------------------------------------------------------
// Write
//------------------------------------------------------------------------

void FLCSRfile::write( uint32_t addr, uint32_t value )
{
    if ( !contains(addr) )
        return; // this should never happen since proc checks legality before calling it

     switch ( addr ) {
        case CSRAddr::MSTATUS:
        // MIE and MPIE are writable; MPP stays Machine.
        regs[addr] = ( value & 0x88 ) | 0x1800;
        break;

        case CSRAddr::MIE:
        // This model supports only the machine timer enable bit.
        regs[addr] = value & 0x80;
        break;

        case CSRAddr::MTVEC:
        case CSRAddr::MEPC:
        // Direct trap mode and four-byte instruction alignment.
        regs[addr] = value & 0xFFFFFFFC;
        break;

        case CSRAddr::MIP:
        // Pending interrupts stay zero in this model.
        break;

        default:
        // Remaining supported registers accept the full value.
        regs[addr] = value;
        break;
    }
  
}

//------------------------------------------------------------------------
// Trap entry
//------------------------------------------------------------------------

uint32_t FLCSRfile::enter_trap( uint32_t pc, uint32_t cause, uint32_t tval )
{
  const uint32_t old_mie = ( regs[CSRAddr::MSTATUS] >> 3 ) & 1;
  regs[CSRAddr::MEPC] = pc & 0xFFFFFFFC;
  regs[CSRAddr::MCAUSE] = cause;
  regs[CSRAddr::MTVAL] = tval;
  regs[CSRAddr::MSTATUS] = ( regs[CSRAddr::MSTATUS] & ~0x88u )
                        | ( old_mie << 7 ) | 0x1800;
  return regs[CSRAddr::MTVEC] & 0xFFFFFFFC;
}

//------------------------------------------------------------------------
// Trap return
//------------------------------------------------------------------------

uint32_t FLCSRfile::return_from_trap()
{
  const uint32_t old_mpie = ( regs[CSRAddr::MSTATUS] >> 7 ) & 1;
  regs[CSRAddr::MSTATUS] = ( regs[CSRAddr::MSTATUS] & ~0x88u )
                        | ( old_mpie << 3 ) | 0x80 | 0x1800;
  return regs[CSRAddr::MEPC];
}
