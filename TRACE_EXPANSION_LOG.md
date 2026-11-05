# Trace expansion implementation log

This file records each change made while implementing the architectural trace
expansion, why it was made, and how it was checked. The design contract remains
in `TRACE_EXPANSION_PLAN.md`.

## 2026-11-01

### Initial audit

- Located the active trace path from `CommitNotif` through the one-entry queue in
  `BlimpV9_csr.v`, then through `InstTraceNotif` and `InstTraceSub`.
- Confirmed that the existing common path carries only PC and integer-register
  writeback. Trap tests separately call `fl_check_trap`, so they do not compare
  trap metadata or CSR state against RTL in the architectural event stream.
- Confirmed that `FLProc::step()` already models ECALL, EBREAK, illegal
  instruction traps, CSR operations, and MRET, making it the appropriate source
  for complete expected events.

### Shared event schema

- Added `types/ArchTrace.v` with the original 424-bit `arch_trace_t` contract:
  PC, conditional GPR write, trap/cause/tval, privileged redirect,
  and the post-event snapshot of mstatus, mie, mtvec, mscratch, mepc, mcause,
  mtval, and mip.
- Added `ARCH_TRACE_BITS` so consumers can mechanically assert the layout width.

### Functional model

- Added `FLCSRfile::Snapshot` and `snapshot()` to expose the existing modeled CSR
  state without duplicating CSR semantics in the trace code.
- Extended `FLTrace` with trap value, redirect information, and CSR snapshot.
- Expanded equality and formatting so active trap/redirect fields and all CSR
  state participate in comparison and diagnostics.
- Added explicit DPI packing in `FLTrace::arch_vrep`. Packing is
  bit-by-bit in SystemVerilog packed-struct order; it does not depend on C++
  object layout.
- Split `FLProc::step()` into a public wrapper and `step_impl()`. The wrapper
  attaches a post-event CSR snapshot to every instruction or trap, avoiding
  error-prone edits to every instruction case.
- Trap entry now records actual tval and redirect target. MRET now records its
  actual mepc redirect.
- Added `fl_arch_trace` to the DPI bridge while retaining legacy `fl_trace` so
  older Blimp variants are not forced onto the new schema in the same change.

### Build dependency repair

- Updated stale l8 CSR test/coverage includes from removed
  `execute_units_l8/CSR.v` and `CSRFile.v` paths to the current l9 execute unit
  and `hw/csr/CSRFile.v`. This was required for CMake dependency discovery and
  was already identified as checkpoint 1 in the design plan.

### Verification status

- `cmake -S . -B build -DCMAKE_Verilog_COMPILER_ID=Verilator`: passed after the
  stale include repair.
- Building `FLProc_test`: the complete `FL_PROC` C++ static library passed.
- The Verilated executable build is currently blocked by the environment's
  default `g++`, which rejects the repository's existing `-std=c++20` and
  `-fcoroutines` flags. This is recorded as a toolchain blocker, not a passing or
  failing architectural trace test.

### Work still in progress

- RTL generation of the complete event, including same-edge CSR next state.
- Unified subscriber comparison and migration away from `fl_check_trap`.
- Packing boundary tests and comprehensive normal/CSR/trap/MRET test runs.

### RTL event production

- Extended `CSRFile.v` with observation-only outputs for the post-event CSR
  snapshot and privileged redirect. The combinational observation defaults to
  current state and applies the same decoded `csr_notif` action and `new_val`
  used by the sequential update, so a queue enqueue on the commit edge sees the
  state that will be installed on that edge.
- The observation reports zero for unimplemented RTL `mie` and `mip`; it does
  not substitute model values. This preserves visibility of the known `mie`
  implementation gap.
- Extended `InstTraceNotif` with an `arch_trace_t` payload while retaining its
  legacy scalar fields for existing Blimp variants and harnesses.
- Widened the `BlimpV9_csr` trace queue to `arch_trace_t` and assembled one event
  from matching commit metadata and CSR post-state.
- Added a simulation fatal when a valid architectural event reaches a full
  trace queue, preventing silent trace loss.

### RTL lint iteration

- Initial V9 CSR lint detected a combinational self-dependency because cause and
  tval validity referenced the `trap` field in the packed value being assembled.
- Replaced that reference with the source exception condition from `csr_notif`.
  This is a source correction, not a lint waiver.

### Unified checker and trap migration

- Added `test/fl/ArchTraceSub.v`. It compares PC and validity bits on every
  event; GPR payload only when write-enable is set; trap details in mcause/mtval;
  redirect target only for privileged redirects; and all eight CSR snapshot
  values on every event.
- Migrated `BlimpV9_csrTestHarness` to use `fl_arch_trace` and the complete
  subscriber when FL checking is enabled. Handwritten expectations remain an
  additional partial check and are not treated as a complete zero-filled event.
- Migrated V9 CSR trap and illegal suites off the separate `fl_check_trap` DPI
  bridge. Their helper now validates handwritten PC/cause, then compares the
  same complete expected event with RTL.
- All three affected V9 CSR lint targets passed after migration.

### Verilator top selection

- The first trap executable build stopped because common dependency modules
  were treated as extra simulation tops and `MULTITOP` warnings are fatal.
- The initial build was later found to be using an unsourced environment with
  Verilator 5.032. The generic `--top-module` edit was reverted pending a clean
  build under the supported C2S2 environment; this log does not classify the
  warning as a repository defect.

### Environment correction and subscriber sampling fix

- The C2S2 setup script is non-operative in a non-interactive command unless
  passed `-f`. The correct automation prefix is
  `source /classes/setup/setup-c2s2.sh -f`.
- The sourced environment supplies GCC 13.3, Verilator 5.050, and VCS 2023.12.
  Earlier commands used GCC 8 until PATH was manually adjusted and Verilator
  5.032 from the old build cache.
- A fresh build directory under the correctly sourced environment reproduced
  `MULTITOP` with Verilator 5.050. The explicit per-test `--top-module` CMake
  option was therefore restored based on sourced-environment evidence.
- The first end-to-end expanded trace run failed broadly. Audit found that the
  new subscriber sampled the payload before a clock edge but tested live `val`
  after the edge, allowing a stale payload to be paired with a new valid event.
- Added sampled `dut_val` alongside the sampled payload, matching the legacy
  subscriber's timing. This is expected to resolve the broad false mismatches;
  the corrected sourced run is pending.
- Verbose rerun then showed the expected DPI struct was corrupt before RTL
  comparison. Root cause: `arch_trace_t` used four-state `logic`, whose DPI ABI
  is `svLogicVecVal`, while the explicit packer writes two-state 32-bit words.
- Changed the shared event fields to packed `bit`, matching `svBitVecVal` and
  the existing `uint32_t*` bridge. Architectural expected values are two-state;
  RTL unknown detection remains a producer/checker responsibility.

### End-to-end results

- Added a checker assertion for the exact `arch_trace_t` width.

### Cause/tval simplification

- Removed event-level `cause` and `tval` from `arch_trace_t` because synchronous
  trap events already carry the same result in post-event `mcause` and `mtval`.
- Reduced the event from 424 to 360 bits and DPI storage from 14 to 12 words.
- Updated directed trap checks to compare the requested cause with `mcause`.
- Kept cause/tval inside the C++ `FLTrace` object for diagnostics and legacy
  helper compatibility; they are no longer part of the architectural payload.
- Added `TRACE_EXECUTION_GUIDE.md` describing the model step, DPI packer, RTL
  producer, queue, and validity-aware comparison flow.
- `BlimpV9_csr_trap_test`: passed all six parameter configurations after the
  DPI ABI and subscriber sampling fixes. Coverage includes ECALL, EBREAK, trap
  CSR updates/redirect, MRET state restoration/redirect, and disabled-MIE state.
- `BlimpV9_csr_csr_test`: reaches the mask test and fails on the documented RTL
  `mie` gap. Representative diagnostics: expected `mie=0x80`, actual zero; the
  corresponding GPR readback is also zero instead of `0x80`.
- `BlimpV9_csr_illegal_test`: times out in the first unknown-encoding case while
  waiting for an RTL architectural event. This exposes a missing RTL event; the
  model produces the expected illegal-instruction trap.
- The legacy `FLProc_test` passed before migration, and all three affected V9 CSR
  lint targets passed. Final checks use the sourced C2S2 Verilator environment.

### Earlier interim design: CSR snapshot monitor (superseded below)

- Added `test/fl/CSRArchTraceMonitor.v`. It receives current implemented CSR
  values from `CSRFile` and the committed `CSRNotif`, then derives the
  post-event CSR snapshot for trap entry, MRET, and CSR writes.
- Changed `hw/csr/CSRFile.v` to expose only current CSR values through ports
  guarded by `ifndef SYNTHESIS`; removed post-event trace prediction from the
  functional CSR file. The sequential CSR update and redirect logic were not
  changed.
- Instantiated the monitor beside `CSRFile` in `hw/top/BlimpV9_csr.v`. Both
  the monitor include and instance are guarded by `ifndef SYNTHESIS`, excluding
  this verification-only prediction logic from synthesis.
- The architectural trace queue and event transport remain in the wrapper;
  this change excludes the CSR post-event prediction logic specifically.
- `git diff --check`, `BlimpV9_csr_trap_test-lint`, and the
  `BlimpV9_csr_trap_test` executable passed under the C2S2 setup. The executable
  covered ECALL, EBREAK, MRET, and disabled-MIE scenarios across six configs.

### Replace CSR snapshots with committed CSR actions

- Replaced the eight repeated CSR values in `arch_trace_t` with action-valid,
  command, address, and source operand fields. Added an explicit 5-bit trap
  cause. The event is now 157 bits (five DPI words).
- Updated `FLTrace` and `FLProc` to record the model's decoded CSR action for
  WRITE/SET/CLEAR, MRET, and trap entry. Removed the per-step CSR snapshot from
  the expected event and removed the now-unused `FLCSRfile::Snapshot` helper.
- Once snapshots were removed, collapsed the temporary `step()` wrapper back
  into a single `FLProc::step()` implementation; the wrapper no longer had work
  to do.
- Updated `BlimpV9_csr` to copy committed action fields directly from
  `CSRNotif`; redirect target/valid come from the CSRFile squash output. The
  separate `CSRArchTraceMonitor` and CSRFile observation ports were removed.
- Updated `ArchTraceSub` to compare only meaningful action payload fields, and
  changed directed trap checks to read `trap_cause`.
- Rewrote the execution guide and marked snapshot-specific sections in the
  earlier plan/walkthrough as historical.
- Rationale: the GPR event already compares the reported write action rather
  than a register-file snapshot. The CSR event now uses the same model. This
  checks reported actions; it does not independently verify CSR state changes.
- `git diff --check`, both V9 CSR lint targets, the `FL_PROC` build, and the
  `BlimpV9_csr_trap_test` executable passed. The trap executable covers six
  parameter configurations, including ECALL, EBREAK, and MRET.
- `BlimpV9_csr_csr_test` passed its earlier directed CSR trace comparisons and
  then failed at the known MIE mask/readback gap: this RTL revision does not
  implement MIE. CSR action fields matched up to that existing failure.
- Replaced the outdated snapshot-era `TRACE_CHANGE_WALKTHROUGH.md` with a short
  current walkthrough covering the event flow, modules, notification fields,
  validity rules, all changed source files, and the limits of action-based
  checking. Expanded it into this code-level walkthrough on 2026-11-01 at the
  user's request.
- After simplifying `FLProc::step()` and expanding the walkthrough, reran both
  V9 CSR lint targets and rebuilt/reran `BlimpV9_csr_trap_test`; all passed.
  `git diff --check` also passed.

### Remove the queue-overflow assertion

- The user clarified that only the simulation-only `$fatal` block should be
  removed; the trace queue and expanded event wiring should remain as they were.
- Removed the `$fatal` assertion from `BlimpV9_csr.v`. No synthesis guards were
  added around the trace payload, queue, interface, or debug logic.
- Updated the walkthrough and execution guide to match this exact scope.
- Both V9 CSR lint targets and the six-configuration trap test pass after the
  removal; `git diff --check` passes.
