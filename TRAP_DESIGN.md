# Trap Design: ECALL / EBREAK / MRET (detected in decode, taken at commit)

Status: final proposed design. No trap RTL has been written. This document is the module-level spec.

Builds on [CSR_DESIGN.md](CSR_DESIGN.md), whose modules are implemented (not yet integrated into a top): the front and back barriers in decode, the per-instruction
`csr_*` fields on `X__WIntf` and in the ROB entry, `CSRNotif`, the standalone `CSRFile`, and the CSR pipe. This design also revises some of those modules; the
revisions are listed in [CSR_DESIGN.md](CSR_DESIGN.md) section 15.

Scope: machine-mode-only `ECALL`, `EBREAK` and `MRET`, with the exception **detected in decode** ("early commit"). Out of scope: top-level integration, all tests,
exceptions detected after issue ("late commit", section 12 describes the path), illegal-instruction exceptions, interrupts, nested traps, a nonzero `mtval`, and
trap support in the FL model.

## 1. The rule

A trap is **detected** where it is known, and **taken** at commit.

- **Detect (early):** decode recognizes `ECALL`/`EBREAK`/`MRET` and gives them the CSR barriers: the op waits until every older instruction has committed, and
  nothing younger enters until it commits. The CSR pipe turns the uop into a per-instruction action: an exception (`exc_val`, `exc_cause`) for `ECALL`/`EBREAK`,
  or a CSR command (`CSR_CMD_MRET`) for `MRET`.
- **Take (at commit, for every trap source):** the action rides `X__WIntf` into the ROB entry. When the instruction commits, the commit unit forwards it on
  `CSRNotif`. `CSRFile` writes the trap CSRs and publishes a `SquashNotif` that redirects fetch to `mtvec` (exception) or `mepc` (`MRET`).

Nothing on the take path depends on where the exception was detected. Late commit only adds more producers of `exc_val` (section 12).

## 2. Background

- [ISA.v](defs/ISA.v) defines `RVI_INST_ECALL` and `RVI_INST_EBREAK` (exact encodings). There is no `MRET` encoding (`0x30200073`).
- [InstDecoder.v](hw/decode_issue/InstDecoder.v) does not decode them. They fall to the `default` row (`val = n`), so decode stalls on them forever.
- `CSRFile` holds only `fflags`, `frm` and `fcsr`. There are no `mstatus`, `mtvec`, `mepc`, `mcause`, `mtval` or `mscratch` CSRs.
- Squash publishers today are decode (`JAL`/`JALR`) and `ControlFlowUnitL6` (taken branches). `SquashUnitL1` arbitrates any number of publishers (a binary tree
  of `SquashUnitL1Helper`s, parameter `p_num_arb`) and grants the oldest by `SeqAge.is_older`.
- On a squash, `FetchUnitL3` sends the request to `squash.target` in the same cycle, holds `D.val` low that cycle, and drops every older in-flight or buffered
  response (`num_to_squash`, `should_drop`). `SeqNumGenL3` frees every number younger than `squash.seq_num` and rewinds its head to `squash.seq_num + 1`.
- The assembler has `ecall`/`ebreak` but not `mret`. The FL model throws on `ECALL`/`EBREAK`.

## 3. Trap semantics (M-mode only, per the RISC-V privileged spec)

| Op | `mepc` | `mcause` | `mtval` | `mstatus` | Redirect target |
|---|---|---|---|---|---|
| `ECALL` | pc of the instruction | 11 (environment call from M-mode) | 0 | `MPIE <- MIE; MIE <- 0` | `{mtvec[31:2], 2'b00}` |
| `EBREAK` | pc of the instruction | 3 (breakpoint) | 0 | as `ECALL` | `{mtvec[31:2], 2'b00}` |
| `MRET` | unchanged | unchanged | unchanged | `MIE <- MPIE; MPIE <- 1` | `mepc` |

- `MPP` (bits 12:11) is hardwired to `2'b11` (M). With M-mode only, the spec's `MPP` updates are no-ops.
- `mtvec` is direct mode only: `mtvec[1:0]` (MODE) is hardwired to 0.
- `mepc[1:0]` is hardwired to 0 (32-bit instruction alignment), on every write path.
- `mtval` is written as 0 on every trap. The spec allows this for `ECALL` and `EBREAK`.
- `mscratch` is a plain read/write CSR with no trap behaviour, so handlers can save a register.
- The trapping instruction itself commits through the ROB and appears in the commit trace with `wen = 0`. The handler's `mepc + 4` return is software's job.

## 4. Design decisions

| # | Decision | Why |
|---|---|---|
| 1 | The trap is **taken at commit**, not in decode | One take path for early and late exceptions. Decode needs no CSR state, no redirect target and no new redirect logic. Under the barriers the trap op is the only instruction past decode when it commits, so the squash only has to reach units that already handle squashes (fetch, decode, `SeqNumGenL3`). Cost: the redirect fires at td+2 instead of td. |
| 2 | **`CSRFile` publishes the squash** | All privileged behaviour (CSR state, trap entry, return, redirect targets, later vectored mode and interrupts) stays in one module. The commit unit stays generic: at commit it forwards the instruction's action. No CSRFile-to-commit read interface is needed. |
| 3 | Exceptions are **per-instruction data** (`exc_val`, `exc_cause`) on `X__WIntf` and in the ROB entry | Any execute unit can raise one later, with its own cause. It needs no age logic and survives squashes naturally, and it matches how the `csr_*` fields already travel ([CSR_DESIGN.md](CSR_DESIGN.md) decision 5). Encoding traps as `csr_cmd` values would leave one spare code and no room for a cause or `mtval`. |
| 4 | **`MRET` is a CSR command** (`CSR_CMD_MRET`), not an exception | It is a return: no cause, and it does not write `mepc`/`mcause`/`mtval`. |
| 5 | **One uop per instruction** (`OP_ECALL`, `OP_EBREAK`, `OP_MRET`) | The decoder table stays uniform, and the CSR pipe maps uop to action exactly as it maps `OP_CSRRW` to write. `num_ops` goes from 44 to 47; the enum stays 6 bits. |
| 6 | **`jal` stays 2 bits** (JAL/JALR only) | Decode does not redirect for traps. |
| 7 | Trap ops get **both barriers**, through the same decoder bit as CSR ops, renamed `is_csr` -> `serialize` | One rule for every serializing op. The back barrier is not strictly needed for precision once the trap is taken at commit, but dropping it breaks "the next commit is the serializing op's own" (the 1-bit `serial_in_flight`). Traps are rare, so the drain cost is accepted. |
| 8 | **`exc_tval` is deferred** | Every trap in scope writes `mtval = 0`. The field is added with the "added in vN" convention when its first producer exists (late load/store faults, illegal instructions). |
| 9 | The squash is **combinational** from ROB dequeue, like `CSRNotif` | It keeps the proven td+2 ordering: the squash, the CSR writes and the barrier release fall in the same cycle. |
| 10 | **Named constants** for CSR commands and exception causes, in [UArch.v](defs/UArch.v) | Three modules (CSR pipe, commit unit, `CSRFile`) share the encodings; magic numbers in each would drift. |

## 5. Behaviour and timeline

```
 Fetch -> [Decode L6] --(D__XIntf)--> [CSR pipe] --(X__WIntf: exc_*, csr_*)--> [Commit unit L4]
   ^         |  serialize: drain wait        |  uop -> exc / csr_cmd                 | ROB entry holds exc_*, csr_*
   |         |  serial_in_flight              |                                       | at dequeue, if exc_val or csr_cmd != 0:
   |         +<------------------------------ CommitNotif ---------------------------+--> CSRNotif --> [CSRFile]
   |                                                                                                        | trap / return:
   +<-------- SquashUnitL1 <------------------------------------------------ SquashNotif (target, seq_num) ---+
```

Life of an `ECALL`:

| Cycle | Event |
|---|---|
| <= td | `ECALL` is in `F_reg`. `serial_in_decode` holds `F.rdy` low; the back barrier holds issue until `drained`. While waiting it is squashable by `should_squash`. |
| td | Issues to the CSR pipe (`X_xfer`). `serial_in_flight` is set. |
| td+1 | The CSR pipe drives `W` with `exc_val = 1`, `exc_cause = EXC_ECALL_M`, `wen = 0`. The commit unit latches it into `X_reg`. |
| td+2 | ROB insert and dequeue in the same cycle (bypass: it is the oldest), so `commit.val`. `CSRNotif` fires. `CSRFile` publishes the squash (target `{mtvec[31:2], 2'b00}`, `seq_num` of the `ECALL`). Fetch sends the handler request; `SeqNumGenL3` rewinds to `seq_num + 1`. `serial_in_flight` clears. At the clock edge `mepc`, `mcause`, `mtval` and `mstatus` update. |
| td+3 | `F.rdy` can reopen. Fetch drops stale responses until `num_to_squash` reaches 0. |
| later | The first handler instruction reaches decode and sees the updated CSRs. |

`EBREAK` differs only in `mcause`. `MRET` is identical except that its target is `mepc` and only `mstatus` changes.

## 6. Component specifications

### 6.1 [UArch.v](defs/UArch.v)

- New uops `OP_ECALL`, `OP_EBREAK`, `OP_MRET` in a `// System` group after the CSR ops, with matching `OP_ECALL_VEC`, `OP_EBREAK_VEC`, `OP_MRET_VEC`. `num_ops = 47`.
- New constants, declared like the existing package parameters:

  ```systemverilog
  // CSR commands, applied at commit
  parameter logic [2:0] CSR_CMD_NONE  = 3'd0;
  parameter logic [2:0] CSR_CMD_WRITE = 3'd1;
  parameter logic [2:0] CSR_CMD_SET   = 3'd2;
  parameter logic [2:0] CSR_CMD_CLEAR = 3'd3;
  parameter logic [2:0] CSR_CMD_MRET  = 3'd4; // 5-7 reserved

  // Exception causes (mcause code, interrupt bit clear)
  parameter logic [4:0] EXC_BREAKPOINT = 5'd3;
  parameter logic [4:0] EXC_ECALL_M    = 5'd11;
  ```

- The interfaces keep plain `logic [2:0]` / `logic [4:0]` fields and do not import the package, as today.

### 6.2 [ISA.v](defs/ISA.v)

- Add under "System Calls": `` `define RVI_INST_MRET 32'b0011000_00010_00000_000_00000_1110011 ``. It is an exact encoding with funct3 `000`, so it cannot overlap the CSR
  patterns.

### 6.3 [InstDecoder.v](hw/decode_issue/InstDecoder.v)

- Rename the `is_csr` output and column to `serialize` ("must be the only instruction in flight").
- Three new rows. They read x0 (never stall on operands, both operands are 0), allocate no register, and do not redirect:

  ```
  `RVI_INST_ECALL:  cs( y, OP_ECALL,  j_n, rx, rx, rx, n, '0, op1_rf, op2_rf, op3_x, y );
  `RVI_INST_EBREAK: cs( y, OP_EBREAK, j_n, rx, rx, rx, n, '0, op1_rf, op2_rf, op3_x, y );
  `RVI_INST_MRET:   cs( y, OP_MRET,   j_n, rx, rx, rx, n, '0, op1_rf, op2_rf, op3_x, y );
  ```

  `imm_sel = '0` (not `'x`) keeps `ImmGen` defined, as the `FENCE` row does.
- `jal` is unchanged (2 bits).

### 6.4 [InstRouter.v](hw/decode_issue/InstRouter.v)

- Three lines in the existing style for `OP_ECALL`, `OP_EBREAK` and `OP_MRET`.

### 6.5 [DecodeIssueUnitL6.v](hw/decode_issue/decode_issue_unit_variants/DecodeIssueUnitL6.v)

- **No logic change.** The barriers apply to every row with `serialize = y`.
- Renames: `decoder_is_csr` -> `decoder_serialize`, `csr_in_decode` -> `serial_in_decode`, `csr_in_flight` -> `serial_in_flight`. The comment block becomes
  "Serialization barriers (CSR and trap instructions)".

### 6.6 [X__WIntf.v](intf/X__WIntf.v)

- Add to the existing v5 block (not yet released, so no new version tag), on both modports:

  | Field | Width | Meaning |
  |---|---|---|
  | `exc_val` | 1 | This instruction raises an exception at commit |
  | `exc_cause` | 5 | mcause code, valid when `exc_val` |

- Contract, stated in the header comment: an execute unit that raises an exception drives `wen = 0` and `csr_cmd = CSR_CMD_NONE`. The exception replaces the
  instruction's normal effects.

### 6.7 Execute units and [ExQueue.v](hw/execute/ExQueue.v)

- ALUL6, ControlFlowUnitL6, IterativeMulDivRemL7, LoadStoreUnitL7 and ALUF tie `exc_val` and `exc_cause` to 0, next to their `csr_*` tie-offs.
- `ExQueue` adds both fields to `msg_t` and forwards them.

### 6.8 [CSR.v](hw/execute/execute_units_l8/CSR.v) (CSR pipe)

- The uop decode produces the whole commit action:

  ```systemverilog
  always_comb begin
    csr_cmd   = CSR_CMD_NONE;
    exc_val   = 1'b0;
    exc_cause = '0;
    unique case (D_reg.uop)
      OP_CSRRW, OP_CSRRWI: csr_cmd = CSR_CMD_WRITE;
      OP_CSRRS, OP_CSRRSI: csr_cmd = CSR_CMD_SET;
      OP_CSRRC, OP_CSRRCI: csr_cmd = CSR_CMD_CLEAR;
      OP_MRET:             csr_cmd = CSR_CMD_MRET;
      OP_ECALL:  begin exc_val = 1'b1; exc_cause = EXC_ECALL_M;    end
      OP_EBREAK: begin exc_val = 1'b1; exc_cause = EXC_BREAKPOINT; end
      default: ;
    endcase
  end
  ```

- Drives `W.exc_val` and `W.exc_cause`. Everything else is unchanged: `W.wen` is 0 because `waddr = x0`, `csr_addr` and `csr_wdata` are 0 (from `op2`/`op1` = x0), and
  the CSR read at address 0 is harmless.
- Header comment: "Execute unit for CSR and system instructions".

### 6.9 [CSRNotif.v](intf/CSRNotif.v)

The commit-time action notification. It gains a `p_seq_num_bits` parameter, as [CommitNotif.v](intf/CommitNotif.v) has.

| Field | Width | Meaning |
|---|---|---|
| `val` | 1 | An action is applied this cycle |
| `cmd` | 3 | `CSR_CMD_*` (ignored when `exc_val`) |
| `addr` | 12 | CSR address |
| `wdata` | 32 | CSR operand (`rs1` value or `zimm`) |
| `exc_val` | 1 | Take an exception |
| `exc_cause` | 5 | mcause code |
| `pc` | 32 | pc of the committing instruction (becomes `mepc`) |
| `seq_num` | `p_seq_num_bits` | Sequence number of the committing instruction (the squash's `seq_num`) |

Publisher: the commit unit. Subscriber: `CSRFile`.

### 6.10 [WritebackCommitUnitL4.v](hw/writeback_commit/writeback_commit_unit_variants/WritebackCommitUnitL4.v)

- Carry `exc_val` and `exc_cause` exactly like the `csr_*` fields: unpack per pipe, mask with `Ex_gnt`, OR-reduce into `_sel` signals (both the `SYNTHESIS` and non-`SYNTHESIS`
  branches), `X_input` (reset to 0 and default 0 in `X_reg_next`), `t_rob_msg`, and `rob_input`.
- Include and import `UArch` for `CSR_CMD_NONE`.
- At dequeue:

  ```systemverilog
  assign csr_notif.val       = commit.val & ( rob_output.exc_val |
                                              ( rob_output.csr_cmd != CSR_CMD_NONE ) );
  assign csr_notif.cmd       = rob_output.csr_cmd;
  assign csr_notif.addr      = rob_output.csr_addr;
  assign csr_notif.wdata     = rob_output.csr_wdata;
  assign csr_notif.exc_val   = rob_output.exc_val;
  assign csr_notif.exc_cause = rob_output.exc_cause;
  assign csr_notif.pc        = rob_output.pc;
  assign csr_notif.seq_num   = commit.seq_num;
  ```

- `complete`, `commit`, `SeqArb` and the trace are unchanged. **No squash port**: the redirect decision belongs to `CSRFile`.

### 6.11 `CSRFile` (moves to `hw/csr/CSRFile.v`)

It is no longer an execute unit: it subscribes to commit-time actions and publishes squashes. Include guard `HW_CSR_CSRFILE_V`.

**Ports:**

```systemverilog
module CSRFile (
  input  logic    clk,
  input  logic    rst,
  CSRIntf.F_intf  csr,        // read port (CSR pipe)
  CSRNotif.sub    csr_notif,  // commit-time actions
  SquashNotif.pub squash      // trap / return redirect
);
```

**State.** Only legal bits are stored; unknown addresses read 0 and ignore writes (unchanged).

| CSR | Addr | Storage | Read value |
|---|---|---|---|
| `fflags` | 0x001 | `fflags[4:0]` | `{27'b0, fflags}` |
| `frm` | 0x002 | `frm[2:0]` | `{29'b0, frm}` |
| `fcsr` | 0x003 | (`frm`, `fflags`) | `{24'b0, frm, fflags}` |
| `mstatus` | 0x300 | `mie`, `mpie` | `{19'b0, 2'b11, 3'b0, mpie, 3'b0, mie, 3'b0}` |
| `mtvec` | 0x305 | `mtvec_base[31:2]` | `{mtvec_base, 2'b00}` |
| `mscratch` | 0x340 | `mscratch[31:0]` | `mscratch` |
| `mepc` | 0x341 | `mepc[31:2]` | `{mepc, 2'b00}` |
| `mcause` | 0x342 | `mcause_int`, `mcause_code[4:0]` | `{mcause_int, 26'b0, mcause_code}` |
| `mtval` | 0x343 | `mtval[31:0]` | `mtval` |

Addresses are `localparam`s in `CSRFile` (it is the only user).

**Read.** One function `read_csr( addr )` serves two combinational read ports: `csr.rdata = read_csr( csr.addr )` for the CSR pipe, and
`old_val = read_csr( csr_notif.addr )` for read-modify-write.

**Write.** Replaces the per-command, per-address nested `case`s with read-modify-write:

```systemverilog
always_comb begin
  case( csr_notif.cmd )
    CSR_CMD_WRITE: new_val = csr_notif.wdata;
    CSR_CMD_SET:   new_val = old_val |  csr_notif.wdata;
    CSR_CMD_CLEAR: new_val = old_val & ~csr_notif.wdata;
    default:       new_val = old_val;
  endcase
end
```

Register updates on `csr_notif.val`, in priority order:

1. `exc_val`: `mepc <= pc[31:2]`, `mcause <= {1'b0, exc_cause}`, `mtval <= 0`, `mpie <= mie`, `mie <= 0`.
2. `cmd == CSR_CMD_MRET`: `mie <= mpie`, `mpie <= 1`.
3. `cmd` is write/set/clear: the CSR selected by `addr` takes the legal bits of `new_val` (`fcsr` writes `frm <= new_val[7:5]`, `fflags <= new_val[4:0]`;
   `mstatus` writes only `mie <= new_val[3]`, `mpie <= new_val[7]`; `mtvec` and `mepc` write only bits 31:2; `mcause` writes bit 31 and bits 4:0).

The existing `fflags`/`frm`/`fcsr` behaviour is unchanged by the refactor. Masking lives in the write, so no path can make `mepc[1:0]` or the `mtvec` mode nonzero.

**Redirect:**

```systemverilog
assign squash.val     = csr_notif.val & ( csr_notif.exc_val |
                                          ( csr_notif.cmd == CSR_CMD_MRET ) );
assign squash.target  = csr_notif.exc_val ? { mtvec_base, 2'b00 } : { mepc, 2'b00 };
assign squash.seq_num = csr_notif.seq_num;
```

The target reads the registers before this cycle's update. That is correct: an exception reads `mtvec` (which it does not write), and `MRET` reads `mepc` (which it does
not write).

### 6.12 Assembler ([asm/inst.h](asm/inst.h))

- Add `MRET` to `inst_name_t` and `{ MRET, "mret", 0x30200073, 0xFFFFFFFF }` to `inst_specs`, next to `ecall`/`ebreak`. The FL model's `switch` has a `default`, so it needs
  no change to build.

### 6.13 Unchanged

`D__XIntf`, `CSRIntf`, `ROB.v`, `SeqAge`, `SeqArb`, `CommitNotif`, `CompleteNotif`, `SquashNotif`, `SquashUnitL1`, `FetchUnitL3`, `SeqNumGenL3`, `RenameTable`, and all tests.

## 7. Invariants

1. **Precise.** Every older instruction has committed before the trap op issues (back barrier). Nothing younger passes decode until the trap op commits (front barrier),
   and the squash discards younger instructions still in fetch.
2. **No stale younger instruction slips in.** In the squash cycle `serial_in_flight` is still 1, so `F.rdy = 0`. From then on `FetchUnitL3` holds `D.val` low until every
   dropped response is gone.
3. **The squash hits only younger instructions.** Its `seq_num` is the trap op's own, and `is_older(x, x) = 0`. The trap op commits normally, and `SeqNumGenL3` frees its
   number through commit, not through the squash.
4. **One squash publisher at a time.** When the trap op commits nothing else is in flight, so decode's and the control-flow unit's squash outputs are idle. The squash
   unit's age comparison would grant the trap op anyway, because it is the oldest.
5. **The handler sees the new state.** The CSR writes land at the td+2 edge, and decode cannot accept an instruction before td+3. As in
   [CSR_DESIGN.md](CSR_DESIGN.md) invariant 3, this requires `CSRFile` to apply `CSRNotif` in the commit cycle; a registered hop would need the barrier to release a cycle later.
6. **The redirect target is current.** Any older write to `mtvec` or `mepc` is a CSR op that committed before the trap op could reach decode, and the target reads the
   registers in the trap op's own commit cycle.
7. **The 1-bit `serial_in_flight` is exact.** The argument in [CSR_DESIGN.md](CSR_DESIGN.md) ("Why the 1-bit clear is safe") applies unchanged: trap ops have the same
   barriers. The squash falls in the trap op's own commit cycle, while decode is still closed.
8. **Wrong-path trap ops never act.** A trap op behind an unresolved branch is killed in `F_reg` by `should_squash` before it can issue, so it never reaches commit.

## 8. Hazards covered

| Hazard | Covered by |
|---|---|
| An older instruction has not finished when the trap is taken | Back barrier |
| A younger instruction executes before the trap | Front barrier, plus the squash for instructions still in fetch |
| A stale fetched instruction enters after the redirect | `serial_in_flight` in the squash cycle, then `FetchUnitL3` dropping |
| The handler reads `mepc`/`mcause`/`mstatus` before the trap writes them | Barrier release in the commit cycle, the same cycle as the write |
| A trap on a wrong path | It never issues (`should_squash` in `F_reg`) |
| `csrw mtvec` or `csrw mepc` immediately before the trap op | The write commits before the trap op enters decode (front barrier) |
| A misaligned `mepc` or a vectored `mtvec` written by software | Masked on every write in `CSRFile` |

## 9. Behaviour details

- **Commit trace.** The trap op appears with its pc and `wen = 0`. The instruction after it in memory never commits before the handler runs.
- **Return address.** `mepc` holds the pc of the `ECALL`/`EBREAK`; the handler adds 4 before `MRET`, as the spec requires.
- **Nested traps.** Not handled specially. A trap inside a handler overwrites `mepc`/`mcause`, as the spec allows when software has not saved them.
- **`MIE`.** Cleared on entry and restored by `MRET`, but there are no interrupt sources yet.
- **Unimplemented CSRs** read 0 and ignore writes. Trapping on them needs the illegal-instruction path (out of scope).

## 10. Costs

- **Latency:** the drain, then the redirect at td+2. Traps are rare.
- **Area:** 6 bits (`exc_val`, `exc_cause`) in each ROB entry, in `X_reg` and in each `ExQueue` entry, plus about 110 bits of new CSR state.
- **Timing:** a new combinational path from ROB dequeue through `CSRNotif`, `CSRFile`, `SquashUnitL1` to fetch and decode. If it fails timing, register the squash and
  release the barrier one cycle later (section 11).

## 11. Alternatives considered

| Alternative | Why not |
|---|---|
| **Take the trap in decode, at issue after the drain** (the previous version of this design) | Redirects about 2 cycles sooner, but needs `mtvec`/`mepc` in decode, a 3-bit `jal`, and a rule against deriving the redirect from `X_xfer` (a combinational loop through `should_squash`). All of it is discarded at late commit. |
| **Redirect from decode before the drain** | Fastest, but a wrong-path trap op can redirect fetch, so correctness depends on squash-ordering details. |
| **Register the commit-time squash** | Shorter timing path, but the barrier release must also move a cycle later, or a stale fetched instruction can enter. Kept as the timing fallback. |
| **Commit unit publishes the squash**, with `CSRFile` exporting `mtvec`/`mepc` to it | The commit unit would encode CSR semantics (which action redirects where) and needs a new CSRFile-to-commit read interface. |
| **Trap codes in `csr_cmd`** | One spare code left after three traps, and no room for a cause or `mtval`. Blocks late exceptions. |
| **One "oldest exception" record in the commit unit** (instead of per-entry fields) | Least area, but needs age comparison on every insert and clearing on every squash, and a stale record can match a reused sequence number. Worth revisiting if ROB area matters. |
| **One `OP_TRAP` uop with the cause as an operand** | Saves two uops, but needs a cause column or operand mux in decode and a cause field `D__XIntf` does not have. Uop space is not the constraint (the enum stays 6 bits). |
| **Only the front barrier for trap ops** | Saves the drain wait, but the "next commit is its own" argument for the 1-bit `serial_in_flight` no longer holds; it would need to track a sequence number. |

## 12. Moving to late exceptions (future)

What stays: `exc_val`/`exc_cause` on `X__WIntf` and in the ROB entry, the `CSRNotif` action path, the `CSRFile` trap entry, return and redirect, the third
`SquashUnitL1` input, and the barriers for CSR ops. A CSR op issues only when nothing older is in flight, so an older faulting instruction can never squash one after issue.

What is added:

1. **Producers.** Execute units drive `exc_val`/`exc_cause` for their own faults, and `exc_tval` is added (fault address or instruction bits). Illegal instructions become
   `OP_ILLEGAL` (cause 2) through the CSR pipe.
2. **Squash past decode.** Every execute pipe, `ExQueue`, the commit unit's `X_reg`, and the ROB (clear younger entries) subscribe to the squash.
3. **Rename recovery.** Restore the rename table and free list from a committed copy (areg -> preg) on a squash. This needs `preg` in the ROB entry and `CommitNotif`.
   A backward ROB walk cannot work, because entries are inserted only when an instruction completes.
4. **Sequence-number reuse.** `SeqNumGenL3` rewinds on a squash, so late results from squashed operations can carry the numbers of new instructions. Add an epoch bit, or
   drain squashed operations before reuse.
5. **Stores and MMIO loads.** `LoadStoreUnitL7` writes memory at execute. Stores must be sent at commit (a store buffer) or held until nothing older can fault, and so must
   loads with side effects (for example the stdin read at `0xF0000004`, which pops the keyboard FIFO).

## 13. Known impacts

- `CSRFile` moves, so [CSRL8_test.v](hw/execute/test/l8/CSRL8_test.v)'s include path breaks. That test is already stale ([CSR_DESIGN.md](CSR_DESIGN.md) section 12) and is left
  unchanged.
- The FL model throws on `ECALL`/`EBREAK` and has no trap state, so trace-compare tests cannot cover traps; directed `check_trace` tests can.
- `num_ops` grows to 47, so every `rv_op_vec` parameter is 47 bits. The `_VEC` parameters are defined relative to `num_ops`, so nothing else changes.
- Older decode units instantiate `InstDecoder` with named ports and leave `is_csr` unconnected; after the rename they leave `serialize` unconnected instead. In older tops,
  trap encodings now decode as valid but no pipe claims them, so decode still stalls on them, as before.

## 14. Implementation order (modules only, no tests)

1. `UArch.v` constants and uops; `ISA.v` `MRET`; assembler `mret`.
2. `InstDecoder` rows and the `serialize` rename; `InstRouter` entries; `DecodeIssueUnitL6` renames.
3. `X__WIntf` exception fields; execute-unit tie-offs; `ExQueue` forwarding.
4. `CSR.v`: uop to action mapping, using the constants.
5. `CSRNotif` fields; `WritebackCommitUnitL4` carries and forwards them.
6. `CSRFile`: move to `hw/csr/`, new CSRs, read-modify-write refactor, trap and return updates, squash port.

## 15. Out of scope

- **Top-level integration.** A top needs: the L6 decode unit, the L4 commit unit, a CSR pipe whose subset includes `OP_CSRR*_VEC`, `OP_ECALL_VEC`, `OP_EBREAK_VEC` and
  `OP_MRET_VEC`, a `CSRFile` connected to `CSRNotif`, and `SquashUnitL1 #(.p_num_arb(3))` with `CSRFile.squash` as the third input.
- All tests, including a `CSRFile` unit test and directed top-level trap tests.
- Everything listed in section 12, illegal-instruction exceptions, interrupts, and FL-model trap support.
