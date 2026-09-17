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
  csrs = MachineCsrs{};  // resets all CSRs to defaults
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
// Read CSR registers
//------------------------------------------------------------------------

bool FLProc::has_csr( uint32_t addr ) const
{
  switch ( addr ) {
    case 0x300: case 0x304: case 0x305: case 0x340:
    case 0x341: case 0x342: case 0x343: case 0x344:
      return true;
    default:
      return false;
  }
}

uint32_t FLProc::read_csr( uint32_t addr )
{
  switch ( addr ) {
    case 0x300: return csrs.mstatus;
    case 0x304: return csrs.mie;
    case 0x305: return csrs.mtvec;
    case 0x340: return csrs.mscratch;
    case 0x341: return csrs.mepc;
    case 0x342: return csrs.mcause;
    case 0x343: return csrs.mtval;
    case 0x344: return 0;  // mip, no timer yet
    default:    return 0;
  }
}

void FLProc::write_csr( uint32_t addr, uint32_t val )
{
  switch ( addr ) {
    case 0x300:
      csrs.mstatus = ( val & 0x00000088 ) | 0x00001800;
      break;
    case 0x304:
      csrs.mie = val & 0x00000080;
      break;
    case 0x305:
      csrs.mtvec = val & 0xFFFFFFFC;
      break;
    case 0x340: csrs.mscratch = val; break;
    case 0x341: csrs.mepc     = val & 0xFFFFFFFC; break;
    case 0x342: csrs.mcause   = val; break;
    case 0x343: csrs.mtval    = val; break;
    case 0x344: break;  // mip exists, but all pending bits are read-only zero
    default:    break;
  }
}

//------------------------------------------------------------------------
// Synchronous machine-mode trap entry
//------------------------------------------------------------------------

FLTrace FLProc::take_trap( uint32_t cause, uint32_t tval )
{
  uint32_t inst_pc = pc;
  uint32_t old_mie = ( csrs.mstatus >> 3 ) & 1;
  csrs.mepc       = inst_pc;
  csrs.mcause     = cause;
  csrs.mtval      = tval;
  csrs.mstatus   = ( csrs.mstatus & ~0x00000088 )
                 | ( old_mie << 7 ) | 0x00001800;
  pc = csrs.mtvec & 0xFFFFFFFC;
  return FLTrace( inst_pc, true, cause );
}

//------------------------------------------------------------------------
// Execution Step
//------------------------------------------------------------------------

FLTrace FLProc::step()
{
  // Fetch the instruction
  uint32_t    binary = mem[pc];
  FLInst      inst( binary );
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

    case ECALL:
      return take_trap( 11 );

      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // ebreak
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case EBREAK:
      return take_trap( 3 );

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
        
      //------------------------------------------------------------------
      // Machine return and Zicsr
      //------------------------------------------------------------------
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
      // mret
      // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    case MRET: {
        uint32_t old_mpie = ( csrs.mstatus >> 7 ) & 1;
        csrs.mstatus = ( csrs.mstatus & ~0x00000088 )
                    | ( old_mpie ? 0x8 : 0 )
                    | 0x00000080
                    | 0x00001800;
        pc = csrs.mepc;
        return FLTrace( inst_pc, 0, 0, false );
      }

      // CSR operations capture the source before writing rd, including
      // when rd == rs1. A zero source field suppresses set/clear writes;
      // a nonzero register containing zero still performs a CSR write.
    case CSRRW:
    case CSRRS:
    case CSRRC:
    case CSRRWI:
    case CSRRSI:
    case CSRRCI: {
      uint32_t addr = inst.csr_addr();
      bool immediate = inst_name == CSRRWI || inst_name == CSRRSI ||
                       inst_name == CSRRCI;
      bool exchange = inst_name == CSRRW || inst_name == CSRRWI;
      bool write = exchange || inst.rs1() != 0;

      // Check legality even when reads or writes are suppressed, before
      // modifying any destination register or CSR.
      if ( !has_csr( addr ) || ( write && ( addr >> 10 ) == 3 ) )
        return take_trap( 2, binary );

      uint32_t source = immediate ? inst.uimm() : regs[inst.rs1()];
      uint32_t old_val = ( exchange && inst.rd() == 0 )
                           ? 0 : read_csr( addr );
      if ( write ) {
        uint32_t new_val = source;
        if ( inst_name == CSRRS || inst_name == CSRRSI )
          new_val = old_val | source;
        else if ( inst_name == CSRRC || inst_name == CSRRCI )
          new_val = old_val & ~source;
        write_csr( addr, new_val );
      }
      if ( inst.rd() != 0 )
        regs[inst.rd()] = old_val;
      pc += 4;
      return FLTrace( inst_pc, inst.rd(), regs[inst.rd()],
                      inst.rd() != 0 );
    }

    default:
      std::string excp =
          std::format( "Unknown instruction: '{}'", inst.mnemonic() );
      throw std::invalid_argument( excp );
  }
}
