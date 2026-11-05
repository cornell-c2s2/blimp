# Blimp architectural trace: code walkthrough

This document describes the **current CSR-action trace**. An earlier working
version carried CSR snapshots and briefly used a `CSRArchTraceMonitor`; that
design was superseded and the monitor was removed. The current trace copies
committed CSR action fields from `CSRNotif`.

## 1. What the trace is for

The trace gives the testbench a per-instruction record of what the RTL says
committed. The functional model independently executes the same instruction
and produces an expected record. The checker compares the records in order.

It is an **event trace**, not a dump of all architectural registers:

- GPRs: report the committing instruction's optional write (`wen`, address,
  data), not all 32 register values.
- CSRs: report the committed CSR action (command, address, source operand), not
  all CSR register values.
- Traps and returns: report trap/cause and any privileged redirect.

This matches the GPR approach: compare the write action reported by RTL with
the write action expected from the model. It does not by itself prove that an
RTL CSR register actually accepted the action; that requires a CSR readback or
state check.

## 2. Current event format

[`types/ArchTrace.v`](types/ArchTrace.v) is the shared packed SystemVerilog
definition. `arch_trace_t` contains 157 meaningful bits and occupies five
32-bit words at the DPI boundary (160 storage bits, with three unused high
bits).

| Field | Width | Meaning | When comparison uses its payload |
|---|---:|---|---|
| `pc` | 32 | PC of the committed instruction | Every event |
| `gen_regs_wen` | 1 | Instruction writes an integer register | Every event |
| `gen_regs_waddr` | 5 | Architectural destination register | Only if `gen_regs_wen` |
| `gen_regs_wdata` | 32 | Value written to that register | Only if `gen_regs_wen` |
| `trap` | 1 | Synchronous exception was taken | Every event |
| `trap_cause` | 5 | Exception cause code | Only if `trap` |
| `redirect_valid` | 1 | Trap-entry or MRET redirect occurred | Every event |
| `redirect_pc` | 32 | Selected redirect target | Only if `redirect_valid` |
| `csr_action_valid` | 1 | Commit-time CSR-related notification is valid | Every event |
| `csr_cmd` | 3 | NONE=0, WRITE=1, SET=2, CLEAR=3, MRET=4 | If action is valid |
| `csr_addr` | 12 | CSR address, such as `0x300` for `mstatus` | Valid WRITE/SET/CLEAR only |
| `csr_wdata` | 32 | Source operand before the CSR operation | Valid WRITE/SET/CLEAR only |

Why `csr_wdata` is an operand: for SET, the result is `old_value | operand`;
for CLEAR, it is `old_value & ~operand`. The notification carries the command
and operand, not that calculated result. The model and RTL each apply the
operation to their own CSR state.

## 3. One instruction through the system

```text
decode/execute CSR instruction
        |
        | command, address, source operand travel with instruction
        v
reorder buffer waits until this instruction can commit
        |
        +--> CommitNotif: PC and GPR writeback, for every committed instruction
        +--> CSRNotif: CSR operation or exception, when one exists
                  |
                  +--> CSRFile applies CSR/trap/MRET action on clock edge
                  +--> BlimpV9_csr copies notification into trace event
                                   |
                                   v
                              trace queue --> testbench subscriber

FLProc executes instruction independently --> expected trace --> comparison
```

The critical distinction is **execution versus commit**. The CSR execute unit
decodes a command but does not make the architectural CSR update there. The
reorder buffer stores the metadata with the instruction. At commit, the WCU
emits `CSRNotif`; `CSRFile` then applies the operation. Thus, a squashed or
uncommitted instruction does not generate a valid CSR notification.

## 4. Where `CSRNotif` comes from

### CSR execute unit: decode and carry the action

In [`hw/execute/execute_units_l9/CSR.v`](hw/execute/execute_units_l9/CSR.v),
the operation decode maps instruction kinds to commands:

```systemverilog
OP_CSRRW, OP_CSRRWI: csr_cmd = CSR_CMD_WRITE;
OP_CSRRS, OP_CSRRSI: csr_cmd = CSR_CMD_SET;
OP_CSRRC, OP_CSRRCI: csr_cmd = CSR_CMD_CLEAR;
OP_MRET:             csr_cmd = CSR_CMD_MRET;
OP_ECALL:            exc_val = 1'b1;
OP_EBREAK:           exc_val = 1'b1;
```

It then puts the decoded metadata on the writeback interface:

```systemverilog
W.csr_cmd   = csr_cmd;
W.csr_addr  = D_reg.op2[11:0];
W.csr_wdata = D_reg.op1; // rs1 value or zimm
W.exc_val   = exc_val;
W.exc_cause = exc_cause;
```

These fields travel alongside the instruction into the WCU/ROB. `CSRNotif`
itself is defined in [`intf/CSRNotif.v`](intf/CSRNotif.v); it is an interface
bundle of wires, not a storage module.

### WCU: only announce the action at commit

In [`WritebackCommitUnitL4.v`](hw/writeback_commit/writeback_commit_unit_variants/WritebackCommitUnitL4.v),
the ROB output is the oldest committing instruction. The key valid equation is:

```systemverilog
csr_notif.val = commit.val &
                (rob_output.exc_val |
                 (rob_output.csr_cmd != CSR_CMD_NONE));
```

Meaning:

- ordinary instruction: `commit.val=1`, but `csr_notif.val=0`;
- CSR instruction: commit is valid and command is non-NONE, so notification is valid;
- trap: commit is valid and `exc_val=1`, so notification is valid even if command is NONE;
- MRET: command is `CSR_CMD_MRET`, so notification is valid.

The other `csr_notif` fields are copied from the ROB output: `cmd`, `addr`,
`wdata`, `exc_val`, `exc_cause`, `pc`, and the commit sequence number. `val` is
the validity qualifier; address/data are not meaningful for trap or MRET events.

## 5. RTL event creation and the queue

### Assemble the event

In [`hw/top/BlimpV9_csr.v`](hw/top/BlimpV9_csr.v), the event is assembled from
existing architectural notifications:

```systemverilog
trace_enq_msg.pc               = commit_notif.pc;
trace_enq_msg.gen_regs_waddr   = commit_notif.waddr;
trace_enq_msg.gen_regs_wdata   = commit_notif.wdata;
trace_enq_msg.gen_regs_wen     = commit_notif.wen;
trace_enq_msg.trap             = csr_notif.val & csr_notif.exc_val;
trace_enq_msg.trap_cause       = csr_notif.exc_cause;
trace_enq_msg.redirect_valid   = squash_arb_notif[2].val;
trace_enq_msg.redirect_pc      = squash_arb_notif[2].target;
trace_enq_msg.csr_action_valid = csr_notif.val;
trace_enq_msg.csr_cmd          = csr_notif.cmd;
trace_enq_msg.csr_addr         = csr_notif.addr;
trace_enq_msg.csr_wdata        = csr_notif.wdata;
trace_enq_val                  = commit_notif.val;
```

`CommitNotif` supplies the instruction PC and GPR write. `CSRNotif` supplies
CSR action and exception metadata. The redirect is taken from the CSR file's
actual squash output. The queue enqueue-valid uses `commit_notif.val`, so the
trace contains ordinary committed instructions too, even when
`csr_action_valid=0`.

### Queue: existed before this change

The `cmn_Queue` was already in `BlimpV9_csr.v`. It previously held the smaller
PC/GPR tuple. The change widened its message to `arch_trace_t`, so it can now
hold the expanded event. The queue separates commit from the trace consumer:
if the consumer is not ready, the event can wait. In debug mode the consumer
controls dequeue readiness, and `debug_stall` pauses issue when the queue has
no room.

After dequeue, `inst_trace.arch` carries the full event. The scalar
`inst_trace.pc/waddr/wdata/wen` outputs remain wired for older consumers.

### Queue overflow assertion: removed

The earlier version had a simulation-only `$fatal` when a valid event met a
full queue. That assertion has been removed at the user's direction. The queue,
expanded payload, enqueue/dequeue handshakes, and debug backpressure remain as
before; only the extra overflow assertion was removed.

## 6. The expected event: C++ functional model and DPI

### Record actions while executing

[`FLProc.cpp`](fl/FLProc.cpp) remains the functional instruction model and
updates its own CSR state as instructions execute:

- CSR instruction: decode WRITE/SET/CLEAR, capture CSR address and source
  operand, perform the model's CSR behavior, then attach those decoded action
  fields to the returned `FLTrace`.
- Trap: `take_trap()` updates model trap state, records trap/cause and expected
  redirect, and marks a valid NONE CSR action for the trap notification.
- MRET: update modeled interrupt-return state, record command MRET and the
  model's `mepc` redirect.
- Ordinary instruction: record PC and optional GPR write; CSR action-valid
  remains false.

[`FLTrace.h`](fl/FLTrace.h) and [`FLTrace.cpp`](fl/FLTrace.cpp) hold those event
fields and compare/format them. The CSR command numbers match `CSRDefs.v`.
`FLCSRfile::Snapshot` was removed because snapshots are no longer part of the
trace; the model still retains its CSR state for executing later instructions.

### Pack for DPI

`fl_arch_trace()` in [`fl/fl_vtrace.cpp`](fl/fl_vtrace.cpp) steps the model once
and calls `FLTrace::arch_vrep()`. That packer in `FLTrace.cpp` clears five
32-bit words, then writes fields in reverse declaration order. SystemVerilog
packed structs put the last-declared field in the least-significant bits. This
explicit packing avoids relying on C++ struct layout and matches the packed
`bit` event's two-state DPI ABI.

[`fl/fl_vtrace.v`](fl/fl_vtrace.v) declares the DPI function with an
`arch_trace_t` output. The old three-word `fl_trace()` remains for compatibility
with legacy users; the V9 CSR harness uses the expanded `fl_arch_trace()`.

The current event is 157 bits, so the C++ packer uses five words. The last word
has three unused high bits, which are zeroed by the packer.

## 7. How `ArchTraceSub` compares the events

[`test/fl/ArchTraceSub.v`](test/fl/ArchTraceSub.v) is a testbench subscriber. It
does not generate events or update architectural state. The harness calls
`check_arch_trace(golden_trace)` after getting one expected event from the
functional model.

The subscriber first checks `$bits(arch_trace_t)` against `ARCH_TRACE_BITS`.
Then it samples both `arch` and `val` together before the clock edge, saves
them in `dut` and `dut_val`, waits for the edge, and compares the saved payload.
Sampling the valid bit with the payload avoids pairing an old event with a new
valid signal after the queue updates.

Comparison validity rules:

1. Always compare PC, GPR write-enable, trap, redirect-valid, and
   CSR-action-valid.
2. Compare GPR destination/data only when GPR write-enable is 1.
3. Compare trap cause only for a trap.
4. Compare redirect target only for a redirect.
5. Compare CSR command whenever action-valid is 1. Compare CSR address/operand
   only for WRITE, SET, and CLEAR; those fields are not meaningful for MRET or
   trap entry.

`check_legacy()` keeps the basic scalar comparison for harness configurations
that do not enable the functional model. It cannot check CSR actions or traps.
The subscriber's `trace()` function is only a line-trace display. If an event
never arrives, the check task waits; the harness's global timeout eventually
fails the test.

## 8. File-by-file change list

| File | Change and reason |
|---|---|
| `types/ArchTrace.v` *(new)* | Define the shared 157-bit event schema for RTL and DPI. |
| `intf/InstTraceNotif.v` | Add the full packed event output while preserving scalar PC/GPR outputs. |
| `hw/top/BlimpV9_csr.v` | Replace the local small message type with `arch_trace_t`; assemble action/trap/redirect fields and expose the full event. The existing queue remains, with a wider payload; the temporary overflow assertion has been removed. |
| `test/fl/ArchTraceSub.v` *(new)* | Add width check, sampled-valid handling, and validity-aware field comparisons; keep the legacy scalar task. |
| `fl/FLTrace.h`, `fl/FLTrace.cpp` | Add action/trap/redirect event fields, equality/formatting, and the explicit DPI packer. Remove CSR snapshot storage. |
| `fl/FLProc.h`, `fl/FLProc.cpp` | Record model CSR action for CSR instructions, traps, and MRET. `step()` directly executes the instruction; there is no snapshot wrapper in the current version. |
| `fl/fl_vtrace.h`, `fl/fl_vtrace.cpp`, `fl/fl_vtrace.v` | Export the new `fl_arch_trace` DPI function and its packed output while retaining legacy `fl_trace`. |
| `hw/top/test/BlimpV9_csrTestHarness.v` | Use the expanded expected event and subscriber; retain manual directed PC/GPR checks; route trap tests through the same event checker. |
| `hw/top/test/BlimpV9_csr_test/BlimpV9_csr_trap_test.v` | Remove the separate trap-only DPI check and compare full trap/MRET trace events. |
| `hw/top/test/BlimpV9_csr_test/BlimpV9_csr_illegal_test.v` | Use the same unified trap event path; current RTL still does not emit an illegal-decode event. |
| `hw/execute/test/l8/CSRL8_test.v`, `hw/execute/test/l8/csr_coverage/coverage/csr_cov.sv` | Repair stale include paths to the current l9 CSR unit and shared `hw/csr/CSRFile.v`, so existing test/lint dependency discovery can find sources. |
| `CMakeLists.txt` | Specify the Verilator top per test executable; fresh supported-toolchain builds otherwise report multiple top modules. |
| `TRACE_EXPANSION_PLAN.md` | Mark implementation status and identify snapshot-oriented portions as historical. |
| `TRACE_EXECUTION_GUIDE.md`, `TRACE_EXPANSION_LOG.md` *(new)* | Document current event flow, known gaps, chronology, reasons, and validation. |
| `TRACE_CHANGE_WALKTHROUGH.md` | This code-level explanation of the current design. |

The temporary `CSRArchTraceMonitor.v` and `CSRFile` observation ports are not
part of the current design. They belonged to the superseded snapshot approach.
The functional CSR update logic in `CSRFile.v` was not changed for the current
action-trace design.

## 9. What was checked and remaining gaps

- `git diff --check`: passed.
- V9 CSR Verilator lint targets: passed.
- `FL_PROC` build: passed.
- `BlimpV9_csr_trap_test`: passed across six configurations, including ECALL,
  EBREAK, trap redirect, MRET redirect, and disabled-MIE trap state.
- `BlimpV9_csr_csr_test`: action trace comparisons proceed through the directed
  CSR cases, then the suite hits the known MIE readback failure. MIE is not
  implemented in this RTL revision, so the CSR read result differs; the action
  trace itself does not check resulting CSR state.
- Illegal instruction tests still expose a separate RTL gap: invalid encodings
  stall in this decode revision instead of producing a committed trap event.

See [`TRACE_EXPANSION_LOG.md`](TRACE_EXPANSION_LOG.md) for the chronological
record, including the superseded snapshot design and current test outcomes.
