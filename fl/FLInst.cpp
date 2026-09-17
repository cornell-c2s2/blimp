//========================================================================
// FLInst.cpp
//========================================================================
// A wrapper around a binary instruction for functional-level operations

#include "asm/assemble.h"
#include "asm/fields.h"
#include "asm/inst.h"
#include "fl/FLInst.h"

//------------------------------------------------------------------------
// Constructors
//------------------------------------------------------------------------

FLInst::FLInst( uint32_t inst ) : binary( inst ) {};
FLInst::FLInst( std::string assembly, uint32_t addr )
    : binary( assemble( assembly.c_str(), &addr ) ) {};

//------------------------------------------------------------------------
// Name
//------------------------------------------------------------------------

inst_name_t FLInst::name() const
{
  return get_inst_spec( binary )->name;
}

std::string FLInst::mnemonic() const
{
  return inst_spec_name( get_inst_spec( binary ) );
}

//------------------------------------------------------------------------
// Registers
//------------------------------------------------------------------------

uint32_t FLInst::rs1() const
{
  return get_rs1( binary );
}
uint32_t FLInst::rs2() const
{
  return get_rs2( binary );
}
uint32_t FLInst::rd() const
{
  return get_rd( binary );
}

//------------------------------------------------------------------------
// Immediates
//------------------------------------------------------------------------

uint32_t FLInst::imm_i() const
{
  return get_imm_i( binary );
}
uint32_t FLInst::imm_s() const
{
  return get_imm_s( binary );
}
uint32_t FLInst::imm_b() const
{
  return get_imm_b( binary );
}
uint32_t FLInst::imm_u() const
{
  return get_imm_u( binary );
}
uint32_t FLInst::imm_j() const
{
  return get_imm_j( binary );
}
uint32_t FLInst::imm_is() const
{
  return get_imm_is( binary );
}

uint32_t FLInst::csr_addr() const
{
  return get_csr( binary );
}

uint32_t FLInst::uimm() const
{
  return get_uimm( binary );
}
