//========================================================================
// FLTrace.cpp
//========================================================================
// Definitions for our processor trace

#include "fl/FLTrace.h"
#include <format>
#include <stdexcept>
#include <string>

//------------------------------------------------------------------------
// Constructor
//------------------------------------------------------------------------

FLTrace::FLTrace( uint32_t pc, uint32_t waddr, uint32_t wdata, bool wen )
    : pc( pc ), waddr( waddr ), wdata( wdata ), wen( wen ) {};

// Assume a struct of the following format:
//
// typedef struct packed {
//   bit        wen;
//   bit  [4:0] waddr;
//   bit [31:0] wdata;
//   bit [31:0] pc;
// } inst_trace;
//
// Pack the bits accordingly (pc is least-significant word)
FLTrace::FLTrace( uint32_t *vstruct )
{
  pc    = vstruct[0];
  wdata = vstruct[1];
  waddr = vstruct[2] & 0x0000001F;
  wen   = ( vstruct[2] >> 5 ) & 0x00000001;
}

FLTrace::FLTrace( uint32_t pc, bool trap, uint32_t cause )
  : trap( trap ), cause( trap ? cause : 0 ), pc( pc ),
    waddr( 0 ), wdata( 0 ), wen( false )
{}

void FLTrace::set_trap_value( uint32_t value ) { tval = value; }
void FLTrace::set_redirect( uint32_t target )
{
  redirect_valid = true;
  redirect_pc = target;
}
void FLTrace::set_csr_action( uint32_t cmd, uint32_t addr, uint32_t data )
{
  csr_action_valid = true;
  csr_cmd = cmd;
  csr_addr = addr;
  csr_wdata = data;
}

//------------------------------------------------------------------------
// Equality
//------------------------------------------------------------------------

bool FLTrace::operator==( const FLTrace &other ) const
{
  if ( pc != other.pc || trap != other.trap ||
       redirect_valid != other.redirect_valid )
    return false;
  if ( trap && ( cause != other.cause || tval != other.tval ) ) return false;
  if ( redirect_valid && redirect_pc != other.redirect_pc ) return false;
  if ( wen != other.wen ||
       ( wen && ( waddr != other.waddr || wdata != other.wdata ) ) ) return false;
  if ( csr_action_valid != other.csr_action_valid ) return false;
  return !csr_action_valid ||
         ( csr_cmd == other.csr_cmd && csr_addr == other.csr_addr &&
           csr_wdata == other.csr_wdata );
}

bool FLTrace::operator!=( const FLTrace &other ) const
{
  return !( *this == other );
}

//------------------------------------------------------------------------
// String representation
//------------------------------------------------------------------------

std::string FLTrace::str() const
{
  std::string str_rep = std::format( "0x{:08x}: ", pc );
  if ( trap ) {
    str_rep += std::format( "trap cause=0x{:08x} tval=0x{:08x}", cause, tval );
  }
  else if ( wen ) {
    str_rep += std::format( "0x{:08x} -> R[{}]", wdata, waddr );
  }
  if ( csr_action_valid )
    str_rep += std::format( " CSR cmd={} addr=0x{:03x} data=0x{:08x}",
                            csr_cmd, csr_addr, csr_wdata );
  if ( redirect_valid )
    str_rep += std::format( " redirect=0x{:08x}", redirect_pc );
  return str_rep;
}

namespace {
void put_bits( uint32_t *words, unsigned &bit, uint32_t value, unsigned width )
{
  for ( unsigned i = 0; i < width; ++i, ++bit )
    if ( ( value >> i ) & 1u ) words[bit / 32] |= 1u << ( bit % 32 );
}
}

// Pack in SystemVerilog packed-struct order. The final declared field (pc)
// occupies the least-significant bits of the svBitVecVal array.
void FLTrace::arch_vrep( uint32_t *words ) const
{
  for ( unsigned i = 0; i < ARCH_WORDS; ++i ) words[i] = 0;
  unsigned bit = 0;
  put_bits( words, bit, csr_wdata, 32 );
  put_bits( words, bit, csr_addr, 12 );
  put_bits( words, bit, csr_cmd, 3 );
  put_bits( words, bit, csr_action_valid, 1 );
  put_bits( words, bit, redirect_pc, 32 );
  put_bits( words, bit, redirect_valid, 1 );
  put_bits( words, bit, cause, 5 );
  put_bits( words, bit, trap, 1 );
  put_bits( words, bit, wdata, 32 );
  put_bits( words, bit, waddr, 5 );
  put_bits( words, bit, wen, 1 );
  put_bits( words, bit, pc, 32 );
}

std::ostream &operator<<( std::ostream &out, const FLTrace &trace )
{
  out << trace.str();
  return out;
}

//------------------------------------------------------------------------
// Verilog Representation
//------------------------------------------------------------------------
// Assume a struct of the following format:
//
// typedef struct packed {
//   bit        wen;
//   bit  [4:0] waddr;
//   bit [31:0] wdata;
//   bit [31:0] pc;
// } inst_trace;
//
// Pack the bits accordingly (pc is least-significant word)

void FLTrace::vrep( uint32_t *vstruct )
{
  if ( trap )
    throw std::invalid_argument(
        "Legacy Verilog retirement trace cannot represent a trap" );
  vstruct[0] = pc;
  vstruct[1] = wdata;
  vstruct[2] = waddr | ( (uint32_t) ( wen ) << 5 );
}
