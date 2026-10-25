# CSR and exception trace expansion plan

Status: design proposal; trace expansion is not implemented.

## 1. Scope and purpose

Provide one architectural event path for normal instructions, synchronous
exceptions, and MRET. The C++ model produces an expected event; RTL produces an
actual event; the SystemVerilog subscriber compares them in architectural order.

Keep the existing CommitNotif interface and its decode consumers unchanged.
CommitNotif serves processor control. The richer instruction trace serves
verification and debug observation.

This phase covers the currently implemented machine-mode CSR set and exceptions.
It does not implement new exceptions, interrupts, memory-effect checking, other
privilege modes, or general branch-target tracing. Those require later work.

## 2. Exact proposed event fields

Use one shared SystemVerilog packed type, provisionally named arch_trace_t.
Field order below is declaration order: first field is most significant.
Widths are explicit so the DPI representation can be checked mechanically.

| Field | Width | Meaning and comparison rule |
|---|---:|---|
| pc | 32 | PC of the instruction associated with this event; always compare. |
| gen_regs_wen | 1 | Whether this event writes an architectural integer register; always compare. |
| gen_regs_waddr | 5 | Architectural destination register number; compare only when gen_regs_wen=1. |
| gen_regs_wdata | 32 | Value written to that register; compare only when gen_regs_wen=1. |
| trap | 1 | This instruction takes a synchronous exception; always compare. |
| cause | 32 | Exception cause; compare only when trap=1. Full width avoids constraining the trace to the current internal cause width. |
| tval | 32 | Value actually installed into mtval for this exception; compare only when trap=1. |
| redirect_valid | 1 | This event applies a trap-entry or MRET redirect; always compare. |
| redirect_pc | 32 | Target actually selected for that redirect; compare only when redirect_valid=1. |
| mstatus | 32 | Architectural CSR value after this event; always compare. |
| mie | 32 | Architectural CSR value after this event; always compare. |
| mtvec | 32 | Architectural CSR value after this event; always compare. |
| mscratch | 32 | Architectural CSR value after this event; always compare. |
| mepc | 32 | Architectural CSR value after this event; always compare. |
| mcause | 32 | Architectural CSR value after this event; always compare. |
| mtval | 32 | Architectural CSR value after this event; always compare. |
| mip | 32 | Architectural CSR value after this event; currently zero in the model. Always compare; do not mask an RTL/model implementation mismatch. |

Total: 424 meaningful bits; DPI storage requires 14 32-bit words (448 bits),
with 24 unused high storage bits. Confirm this with $bits and a packing test.
Do not assume that a C++ object's native memory layout matches this layout.

The output interface additionally has val, meaning that a queued event is
available. val is transport metadata, not part of arch_trace_t. Queue ready is
also transport metadata, not an architectural field.

Initialize inactive payload fields to zero for deterministic packing and logs,
but use the validity conditions above when comparing them.

### Event invariants

- A normal instruction has trap=0 and redirect_valid=0, except MRET.
- A synchronous exception has trap=1, gen_regs_wen=0, and redirect_valid=1.
- MRET has trap=0, gen_regs_wen=0, and redirect_valid=1.
- trap=1 means the faulting instruction did not retire normally; it still emits
  an architectural event so the model and RTL remain aligned.
- A trap event must satisfy tval=mtval in its post-event CSR snapshot.
- No event is emitted for a squashed instruction.
- No instruction may generate duplicate events.
- Ordinary branches and jumps have redirect_valid=0 in this phase: this field
  specifically describes privileged trap/MRET redirects, not every fetch redirect.

There is no separate MRET flag: the actual redirect and resulting CSR state are
checked. Instruction bits or a richer event-kind field can be added later if
explicit instruction identity beyond pc is needed.

### Why a CSR snapshot?

Trap entry can update mepc, mcause, mtval, and mstatus together. A single CSR
address/value pair cannot represent all those changes. The implemented set is
small, so this phase snapshots all eight CSRs after every event. This also checks
that unrelated instructions leave CSR state unchanged.

This is not a complete architectural-state snapshot: it omits the full general-purpose register file
and memory. general-purpose register updates are checked incrementally. Memory effects remain deferred.
Additional CSRs will require extending this fixed schema; a validity-masked CSR
update list can replace snapshots if the implemented set grows substantially.

### Why no privilege field yet?

The current implementation is machine-mode-only. This phase keeps that scope
explicit rather than adding an unobserved mode value. When multiple modes are
implemented, add mode_before and mode_after, each two bits, to both trace producers
and the checker, and define interrupt-event semantics at the same time.

### Why both tval and mtval?

tval describes the exception event; mtval describes resulting CSR state. They
match on trap entry. On later non-trap instructions, mtval still holds state
while the inactive tval field is zero and ignored.

## 3. Example events

### ADDI at PC 0x000 writes x1=-1

pc=0x000; gen_regs_wen=1; gen_regs_waddr=1; gen_regs_wdata=0xffffffff;
trap=0; redirect_valid=0. CSR snapshot equals the state after that instruction.

### ECALL at PC 0x010, mtvec=0x100

pc=0x010; gen_regs_wen=0; trap=1; cause=11; tval=0;
redirect_valid=1; redirect_pc=0x100.
Post-event snapshot includes mepc=0x010, mcause=11, mtval=0, and mstatus with
MPIE copied from the old MIE and MIE cleared. Other CSRs retain their values.

### MRET

pc is the MRET instruction's address; gen_regs_wen=0; trap=0;
redirect_valid=1; redirect_pc is the saved mepc.
The snapshot reflects restored MIE and MPIE=1. In this machine-only model MPP
remains machine mode. mepc itself does not automatically advance.

## 4. RTL collection and cycle alignment

Proposed observation paths:

    WCU -- existing CommitNotif --> decode / other existing consumers
     |
     +-- new commit-event observation --> trace assembly
                                            ^
    CSRFile -- post-event CSR observation ---+
                                            |
                                         trace queue
                                            |
                                    InstTraceNotif --> subscriber

Do not add the eight CSR values to CommitNotif. Do not feed new trace fields into
decode or use trace comparisons to drive architectural control.

The event must describe the actual state immediately after the associated
architectural action. At a commit edge, the trace queue must capture the same
CSR next-state values that CSRFile installs at that edge. Simply connecting the
old CSR registers to the queue input would capture pre-event state.

Preferred implementation: factor CSRFile's update logic into explicit next-state
values; use those same values for register updates and an observation snapshot.
Do not create a second independent implementation of CSR rules in the collector.
Check that observation outputs do not introduce combinational feedback.

Expose the redirect that CSRFile actually generates, not a separately calculated
expected handler target. Capture commit metadata, CSR state, and redirect for the
same instruction in one queue record.

The existing queue is one entry. In normal mode it drains independently of the
subscriber. Add a simulation assertion/fatal for an architectural event when the
queue cannot accept it, accounting for legal simultaneous dequeue/enqueue. Keep
the existing debug stepping flow working. This phase must not silently drop events.
The subscriber must begin checking before normal-mode events drain; it does not
provide readiness or retain an event history.

## 5. Files to edit

All paths are relative to this repository root.

### Shared representation and observation interfaces

| File | Planned change |
|---|---|
| New types/ArchTrace.v | Define arch_trace_t once, with layout, validity rules, and a layout version constant. Follow repository include conventions. |
| intf/InstTraceNotif.v | Carry val plus the shared event payload; update publisher/subscriber modports. |
| New intf/CommitTraceNotif.v | Dedicated WCU observation output for committing exception metadata. Keep it minimal; existing CommitNotif already supplies PC/general-purpose register metadata. |
| New intf/CSRTraceNotif.v | Dedicated CSR observation output for post-event snapshot and privileged redirect information. |

Exact new interface names can follow repository conventions during implementation;
arch_trace_t's field meanings and widths above are the agreed contract.

### RTL producers and assembly

| File | Planned change |
|---|---|
| hw/writeback_commit/writeback_commit_unit_variants/WritebackCommitUnitL4.v | Drive the dedicated exception observation from the selected committing ROB entry. Preserve existing CommitNotif and decode behavior. Carry trap value through the entry if needed. |
| hw/csr/CSRFile.v | Expose the actual post-event CSR values and redirect. Share next-state expressions with the real register updates. |
| hw/top/BlimpV9_csr.v | Connect observation interfaces, construct arch_trace_t, widen the queue through $bits, wire the output, and check for overflow. |

### Trap-value propagation: required audit and dependent edits

CSRNotif currently has exc_val and exc_cause but no exc_tval. Determine what the
current RTL can genuinely report before enabling checks. For ECALL/EBREAK, zero
is expected. Illegal instructions require the selected implementation's actual
mtval behavior to agree with the model; the trace must report actual RTL state.
Do not hide a mismatch by copying the expected model value into the RTL trace.

If trap value is missing, add exc_tval and carry it with its instruction through:

- intf/X__WIntf.v;
- hw/execute/ExQueue.v;
- WCU arbitration, pipeline registers, and ROB payload definition in
  WritebackCommitUnitL4.v;
- intf/CSRNotif.v;
- CSRFile's trap update input;
- relevant exception-producing execute units and all producers' default tie-offs.

Locate actual producers using rg before editing; changing a shared interface can
require updates in other processor variants and unit tests. hw/writeback_commit/ROB.v
is generic over message width, so payload widening alone should not require
changing its storage algorithm.

### C++ model and DPI

| File | Planned change |
|---|---|
| fl/FLTrace.h | Define corresponding event fields and structured CSR snapshot. |
| fl/FLTrace.cpp | Update deterministic initialization, formatting, equality, and explicit DPI packing/unpacking. Traps must be representable. |
| fl/FLProc.cpp | Return one event after each instruction or exception; include actual model CSR snapshot and trap/MRET redirect. |
| fl/FLCSRfile.h and fl/FLCSRfile.cpp | Add read-only snapshot access using the existing CSR state. Keep CSR semantics here. |
| fl/fl_vtrace.v | Import the shared SV type and declare the expanded DPI output/status contract. |
| fl/fl_vtrace.h and fl/fl_vtrace.cpp | Match the generated DPI signature; pack the expanded event; preserve diagnostics. |

Use explicit statuses such as EVENT, HALTED, and ERROR for the model step API.
EVENT includes synchronous exceptions. HALTED must mean deliberate supported
termination, never an arbitrary exception thrown by C++. ERROR must fail checking.
Inspect existing exit-peripheral behavior before assigning termination semantics.
Generate or validate declarations against the simulator-generated DPI header
rather than relying on manually guessed C++ argument types.

### Harness, subscriber, and tests

| File | Planned change |
|---|---|
| test/fl/InstTraceSub.v | Accept one expected event; sample the actual payload when val is asserted; compare with validity conditions and clear diagnostics. |
| hw/top/test/BlimpV9_csrTestHarness.v | Obtain expected events, optionally validate handwritten expectations, then invoke the subscriber. Separate model error from termination. |
| hw/top/test/BlimpV9_csr_test/BlimpV9_csr_trap_test.v | Replace the special trap check with unified event checking. |
| hw/top/test/BlimpV9_csr_test/BlimpV9_csr_illegal_test.v | Same migration; confirm actual filename during implementation. |
| hw/top/test/FLProcTestHarness.v and FLProc_test suites | Adapt model-only checks to the expanded event and remove special trap stepping. |
| hw/top/test/test_cases/directed/csr_test_cases.v | Retain handwritten register expectations; add targeted CSR/event expectations where useful. |
| hw/top/test/test_cases/directed/trap_test_cases.v | Check trap event directly; retain handler-read tests as additional behavioral checks. |
| hw/top/test/test_cases/directed/illegal_test_cases.v | Check cause and trap value through the common path. |
| hw/top/test/csr_trap_trace.cpp | Remove only after all fl_check_trap callers have migrated. |
| CMakeLists.txt | Add dependencies/sources and remove obsolete trap-helper linkage. |

Search all InstTraceNotif and InstTraceSub users before changing their API.
Other tops/harnesses may use the same interface. Either migrate them with explicit
unsupported-field validity or provide a deliberate legacy adapter; never claim
an old producer supports CSR/trap checking by silently substituting zeros.

Keep simple directed-test helpers: callers need not manually populate every CSR
field. Distinguish partial handwritten expectations from the complete model event;
do not confuse an unspecified field with an expected zero.

## 6. Implementation sequence and checkpoints

1. Repair the stale simulator build dependency on
   hw/execute/execute_units_l8/CSR.v. Verify the existing baseline first, recording
   known RTL/model mismatches rather than changing expected values to hide them.
2. Add the event schema and C++ packing support. Test field boundaries, including
   non-word-aligned fields, with distinct values. Assert the 424-bit SV width.
3. Add RTL observation and queue assembly. Check cycle alignment for normal CSR
   writes, trap entry, MRET, back-to-back events, and debug stepping.
4. Update the subscriber and harness, then migrate one normal case and one ECALL
   case end to end before migrating the remaining tests.
5. Migrate model-only, illegal, and trap suites. Delete the old helper after a
   repository-wide search confirms no callers remain.
6. Run the relevant model, unit, and top-level suites across existing supported
   configurations. Add failures that demonstrate detection of wrong CSR values,
   wrong cause/target, missing events, and queue overflow.

Keep changes reviewable as three logical pieces: schema/model API, RTL observation,
and checker/test migration. Do not leave the default build using incompatible
producer and consumer schemas between checkpoints.

## 7. Validation requirements

- Reset snapshot matches the intended implemented CSR defaults.
- Ordinary instructions preserve CSR state.
- All CSR forms preserve current register-write expectations and expose actual
  CSR results, including WARL masks and rd/rs1 aliasing behavior.
- ECALL and EBREAK check PC, cause, zero tval, saved state, and handler redirect.
- Illegal instructions check their supported cause and trap-value behavior.
- MRET checks mstatus restoration and actual return target.
- Traps do not terminate comparison as though the test completed successfully.
- Missing, duplicate, reordered, or dropped events cause a visible failure/timeout.
- Packing tests exercise every field and inactive-field comparison rules.
- Existing implementation gaps remain reported. For example, the directed CSR
  masks test documents an RTL mie mismatch; this plan does not waive that check.

## 8. Deferred work

Memory-effect tracing will later add access kind, address, byte masks, and data,
carried with the instruction to its architectural event. It must distinguish
speculative accesses from architectural effects.

Precise late exceptions also require correct squash/rename recovery and prevention
of younger stores or side-effecting loads becoming visible before older faults are
resolved. Trace expansion observes behavior; it does not implement those mechanisms.

Interrupts need explicit event-boundary semantics and synchronization of external
inputs between RTL and model. Do not model an interrupt as an arbitrary synchronous
exception with a new cause number and assume ordering is solved.
