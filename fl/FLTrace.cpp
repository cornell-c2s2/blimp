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

//------------------------------------------------------------------------
// Equality
//------------------------------------------------------------------------

bool FLTrace::operator==( const FLTrace &other ) const
{
  if ( pc != other.pc || trap != other.trap )
    return false;
  if ( trap )
    return cause == other.cause;
  return wen == other.wen &&
         ( !wen || ( waddr == other.waddr && wdata == other.wdata ) );
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
    str_rep += std::format( "trap cause=0x{:08x}", cause );
  }
  else if ( wen ) {
    str_rep += std::format( "0x{:08x} -> R[{}]", wdata, waddr );
  }
  return str_rep;
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
