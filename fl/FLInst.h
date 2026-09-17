//========================================================================
// FLInst.h
//========================================================================
// A wrapper around a binary instruction for functional-level operations

#ifndef FL_INST_H
#define FL_INST_H

#include "asm/inst.h"
#include <cstdint>
#include <string>

class FLInst {
  //----------------------------------------------------------------------
  // Public accessor functions
  //----------------------------------------------------------------------
 public:
  // Constructors
  FLInst( uint32_t inst );
  FLInst( std::string assembly, uint32_t addr );

  // Metadata
  __attribute__( ( const ) ) inst_name_t name() const;
  __attribute__( ( const ) ) std::string mnemonic() const;

  // Fields
  __attribute__( ( const ) ) uint32_t rs1() const;
  __attribute__( ( const ) ) uint32_t rs2() const;
  __attribute__( ( const ) ) uint32_t rd() const;

  __attribute__( ( const ) ) uint32_t imm_i() const;
  __attribute__( ( const ) ) uint32_t imm_s() const;
  __attribute__( ( const ) ) uint32_t imm_b() const;
  __attribute__( ( const ) ) uint32_t imm_u() const;
  __attribute__( ( const ) ) uint32_t imm_j() const;
  __attribute__( ( const ) ) uint32_t imm_is() const;
  __attribute__( ( const ) ) uint32_t csr_addr() const; // Bits 31:20
  __attribute__( ( const ) ) uint32_t uimm() const; // Bits 19:15, unsigned

  //----------------------------------------------------------------------
  // Protected attrributes
  //----------------------------------------------------------------------
 protected:
  uint32_t binary;
};

#endif  // FL_INST_H
