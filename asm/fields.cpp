//========================================================================
// fields.cpp
//========================================================================
// Utility functions for our assembler to get instruction fields

#include "asm/fields.h"
#include <cstdint>
#include <format>
#include <iomanip>
#include <iostream>
#include <map>
#include <stdexcept>

//------------------------------------------------------------------------
// Internal helper functions
//------------------------------------------------------------------------

bool bit( uint32_t binary, int idx )
{
  return ( binary >> idx ) & 0x1;
}

uint32_t bitmask( int idx )
{
  return (uint32_t) 0x1 << idx;
}

template <typename T>
uint32_t bitslice( T val, int end, int start )
{
  int      len  = end - start + 1;
  uint32_t mask = ( 1 << len ) - 1;

  return (uint32_t) ( val >> start ) & mask;
}

uint32_t repl_upper( bool bit, int start_idx )
{
  bit = bit & 0x1;

  uint32_t mask = 0;
  for ( int i = start_idx; i < 32; i++ ) {
    mask |= ( 1 << i );
  }
  return mask;
}

int32_t get_imm_int( const std::string& imm )
{
  int32_t val;

  // Try conversion - matches decimal (100), hex (0x64), and octal (0144)
  if ( sscanf( imm.c_str(), "%i", &val ) ) {
    return val;
  }

  // No conversion could be done
  std::string excp = std::format( "Invalid immediate: {}", imm );
  throw std::invalid_argument( excp );
}

//------------------------------------------------------------------------
// Register Specifiers
//------------------------------------------------------------------------

const std::map<std::string, uint32_t> reg_masks = {
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // Register Names
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    { "x0", 0 },
    { "x1", 1 },
    { "x2", 2 },
    { "x3", 3 },
    { "x4", 4 },
    { "x5", 5 },
    { "x6", 6 },
    { "x7", 7 },
    { "x8", 8 },
    { "x9", 9 },
    { "x10", 10 },
    { "x11", 11 },
    { "x12", 12 },
    { "x13", 13 },
    { "x14", 14 },
    { "x15", 15 },
    { "x16", 16 },
    { "x17", 17 },
    { "x18", 18 },
    { "x19", 19 },
    { "x20", 20 },
    { "x21", 21 },
    { "x22", 22 },
    { "x23", 23 },
    { "x24", 24 },
    { "x25", 25 },
    { "x26", 26 },
    { "x27", 27 },
    { "x28", 28 },
    { "x29", 29 },
    { "x30", 30 },
    { "x31", 31 },

    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // ABI Names
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    { "zero", 0 },
    { "ra", 1 },
    { "sp", 2 },
    { "gp", 3 },
    { "tp", 4 },
    { "t0", 5 },
    { "t1", 6 },
    { "t2", 7 },
    { "s0", 8 },
    { "fp", 8 },
    { "s1", 9 },
    { "a0", 10 },
    { "a1", 11 },
    { "a2", 12 },
    { "a3", 13 },
    { "a4", 14 },
    { "a5", 15 },
    { "a6", 16 },
    { "a7", 17 },
    { "s2", 18 },
    { "s3", 19 },
    { "s4", 20 },
    { "s5", 21 },
    { "s6", 22 },
    { "s7", 23 },
    { "s8", 24 },
    { "s9", 25 },
    { "s10", 26 },
    { "s11", 27 },
    { "t3", 28 },
    { "t4", 29 },
    { "t5", 30 },
    { "t6", 31 },
};

uint32_t rs1_mask( const std::string& reg_name )
{
  return reg_masks.at( reg_name ) << 15;
}

uint32_t rs2_mask( const std::string& reg_name )
{
  return reg_masks.at( reg_name ) << 20;
}

uint32_t rd_mask( const std::string& reg_name )
{
  return reg_masks.at( reg_name ) << 7;
}

uint32_t get_rs1( uint32_t binary )
{
  return bitslice( binary, 19, 15 );
}

uint32_t get_rs2( uint32_t binary )
{
  return bitslice( binary, 24, 20 );
}

uint32_t get_rd( uint32_t binary )
{
  return bitslice( binary, 11, 7 );
}

std::string get_rs1_id( uint32_t binary )
{
  return "x" + std::to_string( get_rs1( binary ) );
}

std::string get_rs2_id( uint32_t binary )
{
  return "x" + std::to_string( get_rs2( binary ) );
}

std::string get_rd_id( uint32_t binary )
{
  return "x" + std::to_string( get_rd( binary ) );
}

//------------------------------------------------------------------------
// Immediate Specifiers
//------------------------------------------------------------------------

uint32_t imm_i_mask( const std::string& imm )
{
  int32_t imm_val = get_imm_int( imm );

  if ( imm_val > 0xfff ) {
    std::string excp = std::format( "Invalid I-immediate: {}", imm_val );
    throw std::invalid_argument( excp );
  }

  return bitslice( imm_val, 11, 0 ) << 20;
}

uint32_t imm_s_mask( const std::string& imm )
{
  int32_t imm_val = get_imm_int( imm );

  if ( imm_val > 0xfff ) {
    std::string excp = std::format( "Invalid S-immediate: {}", imm_val );
    throw std::invalid_argument( excp );
  }

  uint32_t imm_encoding = 0;
  imm_encoding |= ( bitslice( imm_val, 4, 0 ) << 7 );
  imm_encoding |= ( bitslice( imm_val, 11, 5 ) << 25 );

  return imm_encoding;
}

uint32_t imm_b_mask( const std::string& imm )
{
  int32_t imm_val = get_imm_int( imm );

  if ( imm_val > 0x1fff ) {
    std::string excp = std::format( "Invalid B-immediate: {}", imm_val );
    throw std::invalid_argument( excp );
  }

  if ( imm_val % 2 ) {
    std::string excp = std::format( "Invalid B-immediate: {}", imm_val );
    throw std::invalid_argument( excp );
  }

  uint32_t imm_encoding = 0;
  imm_encoding |= ( bitslice( imm_val, 4, 1 ) << 8 );
  imm_encoding |= ( bitslice( imm_val, 10, 5 ) << 25 );
  imm_encoding |= ( bitslice( imm_val, 11, 11 ) << 7 );
  imm_encoding |= ( bitslice( imm_val, 12, 12 ) << 31 );

  return imm_encoding;
}

uint32_t imm_u_mask( const std::string& imm )
{
  int32_t imm_val = get_imm_int( imm );

  if ( ( imm_val < 0 ) || ( imm_val > 0xFFFFF ) ) {
    std::string excp = std::format( "Invalid U-immediate: {}", imm_val );
    throw std::invalid_argument( excp );
  }

  return (uint32_t) ( imm_val << 12 );
}

uint32_t imm_j_mask( const std::string& imm )
{
  int32_t imm_val = get_imm_int( imm );

  if ( imm_val > 0xfffff ) {
    std::string excp = std::format( "Invalid J-immediate: {}", imm_val );
    throw std::invalid_argument( excp );
  }

  if ( imm_val % 2 ) {
    std::string excp = std::format( "Invalid J-immediate: {}", imm_val );
    throw std::invalid_argument( excp );
  }

  uint32_t imm_encoding = 0;
  imm_encoding |= ( bitslice( imm_val, 10, 1 ) << 21 );
  imm_encoding |= ( bitslice( imm_val, 11, 11 ) << 20 );
  imm_encoding |= ( bitslice( imm_val, 19, 12 ) << 12 );
  imm_encoding |= ( bitslice( imm_val, 20, 20 ) << 31 );

  return imm_encoding;
}

uint32_t imm_is_mask( const std::string& imm )
{
  int32_t imm_val = get_imm_int( imm );

  if ( ( imm_val > 0x1f ) || ( imm_val < 0 ) ) {
    std::string excp =
        std::format( "Invalid Shift-immediate: {}", imm_val );
    throw std::invalid_argument( excp );
  }

  return bitslice( imm_val, 4, 0 ) << 20;
}

uint32_t get_imm_i( uint32_t binary )
{
  return ( (int32_t) binary ) >> 20;
}

uint32_t get_imm_s( uint32_t binary )
{
  uint32_t imm = 0;
  imm |= ( ( (int32_t) binary ) >> 20 ) & 0xFFFFFFE0;
  imm |= ( binary >> 7 ) & 0x0000001F;
  return imm;
}

uint32_t get_imm_b( uint32_t binary )
{
  uint32_t imm = 0;
  imm |= ( ( (int32_t) binary ) >> 20 ) & 0xFFFFF7E0;
  imm |= ( binary >> 7 ) & 0x0000001E;
  imm |= ( binary << 4 ) & 0x00000800;
  return imm;
}

uint32_t get_imm_u( uint32_t binary )
{
  return binary >> 12;
}

uint32_t get_imm_j( uint32_t binary )
{
  uint32_t imm = 0;
  imm |= ( ( (int32_t) binary ) >> 20 ) & 0xFFF007FE;
  imm |= ( binary ) & 0x000FF000;
  imm |= ( binary >> 9 ) & 0x00000800;
  return imm;
}

uint32_t get_imm_is( uint32_t binary )
{
  return ( ( (int32_t) binary ) >> 20 ) & 0x0000001f;
}

std::string get_imm_i_id( uint32_t binary )
{
  return std::to_string( (int) get_imm_i( binary ) );
}

std::string get_imm_s_id( uint32_t binary )
{
  return std::to_string( (int) get_imm_s( binary ) );
}

std::string get_imm_b_id( uint32_t binary )
{
  return std::to_string( (int) get_imm_b( binary ) );
}

std::string get_imm_u_id( uint32_t binary )
{
  return std::to_string( (int) get_imm_u( binary ) );
}

std::string get_imm_j_id( uint32_t binary )
{
  return std::to_string( (int) get_imm_j( binary ) );
}

std::string get_imm_is_id( uint32_t binary )
{
  return std::to_string( (int) get_imm_is( binary ) );
}

//------------------------------------------------------------------------
// CSR Specifiers
//------------------------------------------------------------------------

uint32_t csr_mask( const std::string& csr )
{
  int32_t val = get_imm_int( csr );
  if ( val < 0 || val > 0xfff )
    throw std::invalid_argument( "CSR address must be in [0, 4095]" );
  return (uint32_t) val << 20;
}

uint32_t uimm_mask( const std::string& imm )
{
  int32_t val = get_imm_int( imm );
  if ( val < 0 || val > 31 )
    throw std::invalid_argument( "CSR immediate must be in [0, 31]" );
  return (uint32_t) val << 15;
}

uint32_t get_csr( uint32_t binary )
{
  return ( binary >> 20 ) & 0xfff;
}

uint32_t get_uimm( uint32_t binary )
{
  return ( binary >> 15 ) & 0x1f;
}

std::string get_csr_id( uint32_t binary )
{
  return std::format( "0x{:03x}", get_csr( binary ) );
}

std::string get_uimm_id( uint32_t binary )
{
  return std::to_string( get_uimm( binary ) );
}

//------------------------------------------------------------------------
// Address Specifiers
//------------------------------------------------------------------------

uint32_t addr_b_mask( const std::string& addr, uint32_t pc )
{
  int32_t addr_val = get_imm_int( addr );

  if ( ( addr_val & 0b11 ) != 0 ) {
    std::string excp = std::format( "Unaligned address: {}", addr_val );
    throw std::invalid_argument( excp );
  }

  return imm_b_mask( std::to_string( (int) addr_val - pc ) );
}

uint32_t addr_j_mask( const std::string& addr, uint32_t pc )
{
  int32_t addr_val = get_imm_int( addr );

  if ( ( addr_val & 0b11 ) != 0 ) {
    std::string excp = std::format( "Unaligned address: {}", addr_val );
    throw std::invalid_argument( excp );
  }

  return imm_j_mask( std::to_string( (int) addr_val - pc ) );
}

uint32_t get_addr_b( uint32_t binary, uint32_t pc )
{
  return get_imm_b( binary ) + pc;
}

uint32_t get_addr_j( uint32_t binary, uint32_t pc )
{
  return get_imm_j( binary ) + pc;
}

std::string get_addr_b_id( uint32_t binary, uint32_t pc )
{
  std::stringstream stream;
  stream << "0x" << std::setfill( '0' ) << std::setw( 8 ) << std::hex
         << get_addr_b( binary, pc );
  return stream.str();
}

std::string get_addr_j_id( uint32_t binary, uint32_t pc )
{
  std::stringstream stream;
  stream << "0x" << std::setfill( '0' ) << std::setw( 8 ) << std::hex
         << get_addr_j( binary, pc );
  return stream.str();
}

//------------------------------------------------------------------------
// Fence Arguments
//------------------------------------------------------------------------

uint32_t pred_mask( const std::string& mem_spec )
{
  uint32_t mask = 0;
  if ( mem_spec.find( 'i' ) != std::string::npos ) {
    mask |= bitmask( 27 );
  }
  if ( mem_spec.find( 'o' ) != std::string::npos ) {
    mask |= bitmask( 26 );
  }
  if ( mem_spec.find( 'r' ) != std::string::npos ) {
    mask |= bitmask( 25 );
  }
  if ( mem_spec.find( 'w' ) != std::string::npos ) {
    mask |= bitmask( 24 );
  }
  return mask;
}

uint32_t succ_mask( const std::string& mem_spec )
{
  uint32_t mask = 0;
  if ( mem_spec.find( 'i' ) != std::string::npos ) {
    mask |= bitmask( 23 );
  }
  if ( mem_spec.find( 'o' ) != std::string::npos ) {
    mask |= bitmask( 22 );
  }
  if ( mem_spec.find( 'r' ) != std::string::npos ) {
    mask |= bitmask( 21 );
  }
  if ( mem_spec.find( 'w' ) != std::string::npos ) {
    mask |= bitmask( 20 );
  }
  return mask;
}

std::string get_pred_id( uint32_t binary )
{
  std::string result = "";
  if ( bit( binary, 27 ) ) {
    result += 'i';
  }
  if ( bit( binary, 26 ) ) {
    result += 'o';
  }
  if ( bit( binary, 25 ) ) {
    result += 'r';
  }
  if ( bit( binary, 24 ) ) {
    result += 'w';
  }
  return result;
}

std::string get_succ_id( uint32_t binary )
{
  std::string result = "";
  if ( bit( binary, 23 ) ) {
    result += 'i';
  }
  if ( bit( binary, 22 ) ) {
    result += 'o';
  }
  if ( bit( binary, 21 ) ) {
    result += 'r';
  }
  if ( bit( binary, 20 ) ) {
    result += 'w';
  }
  return result;
}