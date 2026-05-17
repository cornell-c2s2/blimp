//========================================================================
// FLProc.h
//========================================================================
// Definitions for our functional-level processor

#include "asm/assemble.h"
#include "asm/inst.h"
#include "fl/FLProc.h"
#include "fl/parse_elf.h"
#include <format>
#include <iostream>
#include <stdexcept>

//------------------------------------------------------------------------
// Constructor
//------------------------------------------------------------------------

FLProc::FLProc() : pc( 0x000 )
{
  // Add peripherals
  mem.add_peripheral( &terminal );
  mem.add_peripheral( &exit );
};

//------------------------------------------------------------------------
// Reset
//------------------------------------------------------------------------

void FLProc::reset()
{
  pc = 0x000;
  mem.clear();
}

//------------------------------------------------------------------------
// Initialize Memory
//------------------------------------------------------------------------

void FLProc::init( uint32_t addr, uint32_t inst )
{
  mem[addr] = inst;
}
void FLProc::init( uint32_t addr, std::string assembly )
{
  mem[addr] = assemble( assembly.c_str(), &addr );
}

//------------------------------------------------------------------------
// Execution Step
//------------------------------------------------------------------------

FLTrace FLProc::step()
{
  // Fetch the instruction
  FLInst      inst( mem[pc] );
  inst_name_t inst_name = inst.name();
  uint32_t    inst_pc   = pc;

  switch ( inst_name ) {
      //------------------------------------------------------------------
      // RV32I
      //------------------------------------------------------------------

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // add
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case ADD:
      regs[inst.rd()] = regs[inst.rs1()] + regs[inst.rs2()];
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // sub
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SUB:
      regs[inst.rd()] = regs[inst.rs1()] - regs[inst.rs2()];
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // and
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case AND:
      regs[inst.rd()] = regs[inst.rs1()] & regs[inst.rs2()];
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // or
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case OR:
      regs[inst.rd()] = regs[inst.rs1()] | regs[inst.rs2()];
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // xor
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case XOR:
      regs[inst.rd()] = regs[inst.rs1()] ^ regs[inst.rs2()];
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // slt
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SLT:
      regs[inst.rd()] =
          ( (int32_t) regs[inst.rs1()] ) < ( (int32_t) regs[inst.rs2()] );
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // sltu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SLTU:
      regs[inst.rd()] = regs[inst.rs1()] < regs[inst.rs2()];
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // sra
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SRA:
      regs[inst.rd()] =
          ( (int32_t) regs[inst.rs1()] ) >> ( regs[inst.rs2()] & 0x1f );
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // srl
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SRL:
      regs[inst.rd()] = regs[inst.rs1()] >> ( regs[inst.rs2()] & 0x1f );
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // sll
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SLL:
      regs[inst.rd()] = regs[inst.rs1()] << ( regs[inst.rs2()] & 0x1f );
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // addi
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case ADDI:
      regs[inst.rd()] = regs[inst.rs1()] + inst.imm_i();
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // andi
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case ANDI:
      regs[inst.rd()] = regs[inst.rs1()] & inst.imm_i();
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // ori
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case ORI:
      regs[inst.rd()] = regs[inst.rs1()] | inst.imm_i();
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // xori
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case XORI:
      regs[inst.rd()] = regs[inst.rs1()] ^ inst.imm_i();
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // slti
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SLTI:
      regs[inst.rd()] =
          ( (int32_t) regs[inst.rs1()] ) < ( (int32_t) inst.imm_i() );
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // sltiu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SLTIU:
      regs[inst.rd()] = regs[inst.rs1()] < inst.imm_i();
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // srai
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SRAI:
      regs[inst.rd()] = ( (int32_t) regs[inst.rs1()] ) >> inst.imm_is();
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // srli
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SRLI:
      regs[inst.rd()] = regs[inst.rs1()] >> inst.imm_is();
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // slli
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SLLI:
      regs[inst.rd()] = regs[inst.rs1()] << inst.imm_is();
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // lui
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case LUI:
      regs[inst.rd()] = inst.imm_u() << 12;
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // auipc
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case AUIPC:
      regs[inst.rd()] = pc + ( inst.imm_u() << 12 );
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // lb
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case LB:
      regs[inst.rd()] =
          (int8_t) mem.loadb( regs[inst.rs1()] + inst.imm_i() );
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // lh
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case LH:
      regs[inst.rd()] =
          (int16_t) mem.loadh( regs[inst.rs1()] + inst.imm_i() );
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // lw
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case LW:
      regs[inst.rd()] = mem.loadw( regs[inst.rs1()] + inst.imm_i() );
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // lbu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case LBU:
      regs[inst.rd()] = mem.loadb( regs[inst.rs1()] + inst.imm_i() );
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // lhu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case LHU:
      regs[inst.rd()] = mem.loadh( regs[inst.rs1()] + inst.imm_i() );
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // sb
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SB:
      mem.storeb( regs[inst.rs1()] + inst.imm_s(), regs[inst.rs2()] );
      pc = pc + 4;
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // sh
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SH:
      mem.storeh( regs[inst.rs1()] + inst.imm_s(), regs[inst.rs2()] );
      pc = pc + 4;
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // sw
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case SW:
      mem.storew( regs[inst.rs1()] + inst.imm_s(), regs[inst.rs2()] );
      pc = pc + 4;
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // jal
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case JAL:
      regs[inst.rd()] = pc + 4;
      pc              = pc + inst.imm_j();
      return FLTrace( inst_pc, inst.rd(), inst_pc + 4, inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // jalr
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case JALR:
      pc              = ( regs[inst.rs1()] + inst.imm_i() ) & 0xfffffffe;
      regs[inst.rd()] = inst_pc + 4;
      return FLTrace( inst_pc, inst.rd(), inst_pc + 4, inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // beq
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case BEQ:
      if ( regs[inst.rs1()] == regs[inst.rs2()] ) {
        pc = pc + inst.imm_b();
      }
      else {
        pc = pc + 4;
      }
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // bne
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case BNE:
      if ( regs[inst.rs1()] != regs[inst.rs2()] ) {
        pc = pc + inst.imm_b();
      }
      else {
        pc = pc + 4;
      }
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // blt
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case BLT:
      if ( ( (int32_t) regs[inst.rs1()] ) <
           ( (int32_t) regs[inst.rs2()] ) ) {
        pc = pc + inst.imm_b();
      }
      else {
        pc = pc + 4;
      }
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // bge
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case BGE:
      if ( ( (int32_t) regs[inst.rs1()] ) >=
           ( (int32_t) regs[inst.rs2()] ) ) {
        pc = pc + inst.imm_b();
      }
      else {
        pc = pc + 4;
      }
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // bltu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case BLTU:
      if ( regs[inst.rs1()] < regs[inst.rs2()] ) {
        pc = pc + inst.imm_b();
      }
      else {
        pc = pc + 4;
      }
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // bgeu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case BGEU:
      if ( regs[inst.rs1()] >= regs[inst.rs2()] ) {
        pc = pc + inst.imm_b();
      }
      else {
        pc = pc + 4;
      }
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // fence
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // NOP

    case FENCE:
      pc = pc + 4;
      return FLTrace( inst_pc, 0, 0, 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // ecall
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // NOP

    case ECALL:
      throw std::invalid_argument(
          "No surrounding instruction environment" );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // ebreak
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // NOP

    case EBREAK:
      throw std::invalid_argument(
          "No surrounding debugging environment: '{}'" );

      //------------------------------------------------------------------
      // RV32M
      //------------------------------------------------------------------

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // mul
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case MUL:
      regs[inst.rd()] = regs[inst.rs1()] * regs[inst.rs2()];
      pc              = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // mulh
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case MULH:
      regs[inst.rd()] =
          ( ( ( (int64_t) ( (int32_t) regs[inst.rs1()] ) ) *
              ( (int64_t) ( (int32_t) regs[inst.rs2()] ) ) ) >>
            32 ) &
          0xFFFFFFFF;
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // mulhu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case MULHU:
      regs[inst.rd()] = ( ( ( (uint64_t) regs[inst.rs1()] ) *
                            ( (uint64_t) regs[inst.rs2()] ) ) >>
                          32 ) &
                        0xFFFFFFFF;
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // mulhsu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case MULHSU:
      regs[inst.rd()] = ( ( ( (int64_t) ( (int32_t) regs[inst.rs1()] ) ) *
                            ( (uint64_t) regs[inst.rs2()] ) ) >>
                          32 ) &
                        0xFFFFFFFF;
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // div
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case DIV:
      if ( regs[inst.rs2()] == 0 ) {  // Divide by 0
        regs[inst.rd()] = -1;
      }
      else if ( ( regs[inst.rs1()] == 0x80000000 ) &&
                ( regs[inst.rs2()] == 0xffffffff ) ) {  // Overflow
        regs[inst.rd()] = 0x80000000;
      }
      else {
        regs[inst.rd()] = ( (int32_t) regs[inst.rs1()] ) /
                          ( (int32_t) regs[inst.rs2()] );
      }
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // divu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case DIVU:
      if ( regs[inst.rs2()] == 0 ) {  // Divide by 0
        regs[inst.rd()] = -1;
      }
      else {
        regs[inst.rd()] = regs[inst.rs1()] / regs[inst.rs2()];
      }
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // rem
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case REM:
      if ( regs[inst.rs2()] == 0 ) {  // Divide by 0
        regs[inst.rd()] = regs[inst.rs1()];
      }
      else if ( ( regs[inst.rs1()] == 0x80000000 ) &&
                ( regs[inst.rs2()] == 0xffffffff ) ) {  // Overflow
        regs[inst.rd()] = 0;
      }
      else {
        regs[inst.rd()] = ( (int32_t) regs[inst.rs1()] ) %
                          ( (int32_t) regs[inst.rs2()] );
      }
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // remu
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case REMU:
      if ( regs[inst.rs2()] == 0 ) {  // Divide by 0
        regs[inst.rd()] = regs[inst.rs1()];
      }
      else {
        regs[inst.rd()] = regs[inst.rs1()] % regs[inst.rs2()];
      }
      pc = pc + 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );

    default:
      std::string excp =
          std::format( "Unknown instruction: '{}'", inst.mnemonic() );
      throw std::invalid_argument( excp );
  }
}