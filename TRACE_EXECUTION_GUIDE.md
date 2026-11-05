# Architectural trace execution guide

## What one trace event records

The trace records the instruction PC, its optional GPR write, trap and redirect
information, and the committed CSR **action**. It does not contain a full GPR or
CSR register snapshot. This makes the CSR trace follow the same event-based
approach as GPR writeback.

The CSR action fields are `csr_action_valid`, `csr_cmd`, `csr_addr`, and
`csr_wdata`. The data field is the source operand before the CSR operation is
applied. For WRITE, SET, and CLEAR, the checker compares all three action values.
For MRET or a trap, it compares the action-valid and command plus the relevant
trap/redirect fields; address and operand are not meaningful for those actions.

## Expected event: functional model

`FLProc::step()` executes one instruction. A CSR instruction is decoded into the
same action category as RTL: WRITE, SET, or CLEAR, with its CSR address and
source operand. MRET records the MRET command. Trap entry records the exception
and cause. The functional model still updates its own CSR state so later
instructions execute correctly, but the trace does not serialize that state.

`fl_arch_trace()` is the DPI entry point. It calls `FLProc::step()` once and
`FLTrace::arch_vrep()` packs the expected event into five 32-bit words (157
meaningful bits). The packer follows SystemVerilog packed-struct order; it does
not copy a C++ object or depend on compiler layout.

## RTL event: commit notifications

The writeback/commit unit publishes the committing instruction's PC and GPR
writeback through `CommitNotif`. It publishes the committed CSR operation or
exception through `CSRNotif`. `BlimpV9_csr` copies those notification fields
into the architectural trace event. Redirect validity and target come from the
CSRFile's squash notification, which is the actual redirect output.

The CSR notification is generated at commit, so speculative or squashed CSR
operations do not become trace events. The existing queue holds each expanded
event until the trace consumer accepts it. No extra queue-overflow `$fatal`
assertion is currently present; queue handshaking and debug backpressure remain.

## Comparison

`BlimpV9_csrTestHarness::check_trace()` obtains one expected event from the
functional model. `ArchTraceSub::check_arch_trace()` waits for the next RTL
event and compares:

- PC, GPR write-enable, trap, redirect-valid, and CSR-action-valid every event;
- GPR destination/data only when GPR write-enable is set;
- trap cause only for traps;
- redirect target only for redirects;
- CSR command/address/operand for WRITE, SET, and CLEAR actions.

Thus the trace checks the reported CSR action, like it checks the reported GPR
write. It does not independently confirm the CSR registers' resulting values;
that would require reading back or reconstructing CSR state as a separate check.
The event-by-event comparison still detects wrong, missing, duplicate, or
reordered committed actions.

## Current implementation gaps

- The RTL CSR file does not implement MIE or MIP state, though the functional
  model supports MIE and fixes MIP at zero. Readback tests remain necessary to
  expose that gap; the action trace alone does not prove a CSR write took effect.
- Unknown illegal encodings currently do not reach a committed RTL trace event;
  the illegal suite times out waiting for that event.
- Memory architectural effects are not part of this trace version.
