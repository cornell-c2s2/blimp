//========================================================================
// ArchTrace.v
//========================================================================
// Shared architectural event representation used by the RTL and FL model.

`ifndef TYPES_ARCH_TRACE_V
`define TYPES_ARCH_TRACE_V

typedef struct packed {
  bit [31:0] pc;             // PC of the instruction that generated this event
  bit        gen_regs_wen;   // 1 when the instruction writes a general-purpose register
  bit  [4:0] gen_regs_waddr; // Destination register address; meaningful only when wen=1
  bit [31:0] gen_regs_wdata; // Data written to the destination register; meaningful only when wen=1

  bit        trap;           // Did this instruction generate a synchronous exception?
  bit  [4:0] trap_cause;     // Exception cause; meaningful only when trap=1
  bit        redirect_valid; // Are we entering a trap or returning from one with MRET?
  bit [31:0] redirect_pc;    // Trap entry: mtvec target; MRET: address stored in mepc

  // Committed CSR action; meaningful only when csr_action_valid=1.
  bit        csr_action_valid;
  bit  [2:0] csr_cmd;        // 1=WRITE, 2=SET, 3=CLEAR, 4=MRET
  bit [11:0] csr_addr;       // CSR addressed by the committed instruction
  bit [31:0] csr_wdata;      // Source operand, before WRITE/SET/CLEAR is applied
} arch_trace_t;

localparam int ARCH_TRACE_BITS = 157; // Exact packed width used by RTL and DPI

`endif // TYPES_ARCH_TRACE_V
