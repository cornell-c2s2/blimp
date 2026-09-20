# Trap Design: ECALL / EBREAK / MRET (early exceptions in decode)

Status: proposed design. No trap RTL has been written. This builds on [CSR_DESIGN.md](CSR_DESIGN.md), whose modules are implemented (not yet integrated into a top). It provides the front and back
barriers, the `X__WIntf` `csr_*` fields carried in the ROB entry, `CSRNotif`, the standalone `CSRFile`, and the CSR pipe.

Scope: machine-mode-only handling of `ECALL`, `EBREAK` and `MRET`, where the exception is **detected and initiated in decode** ("early exception commit").
Out of scope: illegal-instruction exceptions (decode keeps stalling on unsupported encodings, as it does today), `WFI`, `FENCE.I`, nested traps, interrupts, and
exceptions raised at ROB commit ("late commit": memory faults, etc.). Section 9 describes what late commit would change.

## 1. Idea in one paragraph

Decode recognizes a trap op and treats it exactly like a CSR instruction: it has the **same front and back barriers** (it waits in decode until every
older instruction has committed, and nothing younger enters until it commits). It issues to the CSR pipe, carries its request in the `X__WIntf` `csr_*`
fields into the ROB entry, and its effects are applied at commit through `CSRNotif`, using new `cmd` encodings that write several CSRs in parallel.
The **redirect** fires from decode's existing `squash_pub` at issue, after the drain, with the target read from `mtvec` or `mepc`. Decode gets no CSR
write port and `CSRFile` keeps a single writer.

## 2. Current state

- [ISA.v](defs/ISA.v) defines `RVI_INST_ECALL` and `RVI_INST_EBREAK` (exact encodings). **`MRET` has no encoding** (`0x30200073`).
- [InstDecoder.v](hw/decode_issue/InstDecoder.v) does not decode any of them. They fall to `default`, which sets `val = n` and everything else to `'x`. With `val = n`,
  `decoder_val` stays 0, `F.rdy` never asserts, and decode/fetch **stall** on them. This design leaves that behaviour as is for every encoding other than the three trap ops.
- The top levels say `RV32IM (no exceptions)`. There are no `mstatus`, `mtvec`, `mepc`, `mcause`, `mtval` or `mscratch` CSRs.
- Decode already has a redirect mechanism (`squash_pub`, `squash_sent`) used for `JAL`/`JALR`
  ([DecodeIssueUnitL6.v](hw/decode_issue/decode_issue_unit_variants/DecodeIssueUnitL6.v)).

## 3. Trap semantics (M-mode only, per the RISC-V privileged spec)

CSRs added to `CSRFile`: `mstatus` (0x300; fields `MIE` bit 3, `MPIE` bit 7, `MPP` bits 12:11), `mscratch` (0x340), `mtvec` (0x305), `mepc` (0x341), `mcause` (0x342),
`mtval` (0x343).

| Op | `mepc` | `mcause` | `mtval` | `mstatus` | Redirect target |
|---|---|---|---|---|---|
| `ECALL` | pc of the instruction | 11 (ecall from M-mode) | 0 | `MPIE <- MIE; MIE <- 0; MPP <- M` | `mtvec` base |
| `EBREAK` | pc of the instruction | 3 (breakpoint) | 0 | as `ECALL` | `mtvec` base |
| `MRET` | unchanged | unchanged | unchanged | `MIE <- MPIE; MPIE <- 1; MPP <- M` | `mepc` |

Notes:

- `mtvec`: direct mode only. Target is `{mtvec[31:2], 2'b00}`. Vectored mode only affects interrupts.
- `mepc[1:0]` is hardwired to 0 (32-bit instruction alignment), and the `MRET` target uses it as stored.
- With M-mode only, `MPP` is effectively always `M`.
- `mtval` is always written as 0 on a trap (the spec allows this for `ECALL` and `EBREAK`).
- `mscratch` is a plain 32-bit read/write CSR with no trap behaviour. It is written by the ordinary CSR instructions through the existing `CSRNotif` write/set/clear path, so handlers
  can save a register. It needs no trap logic.

## 4. Decode changes

1. **Encodings.** Add `RVI_INST_MRET` to [ISA.v](defs/ISA.v) (naming to match the file's convention).
2. **New uops.** `OP_ECALL`, `OP_EBREAK`, `OP_MRET` in [UArch.v](defs/UArch.v). `num_ops` is 44 and full, so bump it to 47 (the enum stays 6 bits; the `rv_op_vec` width grows) and add the
   matching `_VEC` parameters. `InstRouter.v` also needs an entry for each new uop (see [CSR_DESIGN.md](CSR_DESIGN.md) section 6.11).
3. **`InstDecoder` entries** for `ECALL`, `EBREAK`, `MRET`: `val = y`, `raddr0 = raddr1 = rx`, `waddr = rx`, `wen = n`, `op1_sel = op1_rf`, `op2_sel = op2_rf`, so they never stall on operands and
   allocate no register. Reading `x0` makes `op1 = op2 = 0`, which is exactly the `mtval` operand and the (unused) CSR address they need. **`is_csr = 1`**, so the barriers apply to them exactly
   as to CSR instructions.
4. **Everything else is unchanged.** Unsupported encodings (illegal instructions, and also `WFI` and `FENCE.I`) keep the current `default` row and still stall decode. No `OP_ILLEGAL` uop is added.
5. **Barriers.** No new logic. `csr_class` is built from the `is_csr` control column (`F_reg.val & decoder_val & decoder_is_csr`), so the front barrier (`csr_active` and the `F.rdy` gate) and the back
   barrier (the `drained` term on the router `val`) in `DecodeIssueUnitL6` already apply.
6. **Redirect.** Widen the `jal` selector from 2 to 3 bits: `0` none, `1` `JAL`, `2` `JALR`, `3` trap (target `mtvec` base), `4` `MRET` (target `mepc`). `squash_pub.val` keeps its `JAL`/`JALR`
   condition, and for codes `3` and `4` it fires on `F_reg.val & drained & !stall_pending & !squash_sent` (the same shape, reusing `squash_sent`). The target mux gains the two new arms.
   **The redirect must not be derived from `X_xfer`.** `X_xfer` depends on `should_squash`, which depends on `squash_sub`, which is driven from `squash_pub`; using it would create a combinational loop.
7. **New decode input:** a `CSRTrapIntf` (below) carrying `mtvec` and `mepc` from `CSRFile`.

## 5. Execute, commit and CSRFile changes

- **New interface `CSRTrapIntf`** (`intf/CSRTrapIntf.v`, name provisional). It carries the two read-only values decode needs for the redirect, `mtvec[31:0]` and `mepc[31:0]`, with side-named modports:
  `F_intf` (`CSRFile` side, outputs) and `D_intf` (decode side, inputs), following the convention of `CSRIntf`/`D__XIntf`. It is a separate interface from `CSRIntf`, which stays the read port
  used by the CSR pipe.
- **CSR pipe.** Its subset includes the three trap uops. The only change to `CSR.v` is three new arms in its `csr_cmd` `case`, mapping the trap uops to `100`-`110`. Everything else already works:
  `W.wen = D_reg.val & (waddr != 0)` is 0 because decode gives `waddr = x0`, `W.csr_addr = op2[11:0]` is 0 because decode reads `x0` for `op2`, and `W.csr_wdata = op1` is 0. The CSR read result on
  `W.wdata` is unused (`wen = 0`). `W.pc` already carries the instruction's pc.
- **`csr_cmd` encodings** (using the space reserved in [CSR_DESIGN.md](CSR_DESIGN.md)): `100` `ECALL`, `101` `EBREAK`, `110` `MRET`. `111` stays unused.
- **Commit unit (`WritebackCommitUnitL4`).** No new storage: the `pc` is already in the ROB entry. `CSRNotif` gains a `pc` field (added in the repo's "added in vN" style), driven from `rob_output.pc`.
- **`CSRFile`:**
  - Adds `mstatus`, `mscratch`, `mtvec`, `mepc`, `mcause` and `mtval`. `mscratch` (and the other CSRs, for ordinary CSR instructions) use the existing write/set/clear path.
  - On a trap `cmd`, in one cycle: writes `mepc <- pc` (not for `MRET`), `mcause <- f(cmd)` (11 for `ECALL`, 3 for `EBREAK`, not for `MRET`), `mtval <- 0`, and updates `mstatus` as in section 3. The cause
    code is derived from `cmd`, so it does not have to travel with the request.
  - Drives `CSRTrapIntf` with the current `mtvec` and `mepc`.
- The ROB, `CommitNotif`, `SeqArb` and `ExQueue` behave as in [CSR_DESIGN.md](CSR_DESIGN.md); no further changes.

## 6. Timeline: `ECALL`

1. **t0..td.** `ECALL` is in `F_reg`. `csr_class` is true, so `F.rdy` is low, and the back barrier holds it until every older instruction has committed. Fetch keeps prefetching sequential
   instructions until its 8-entry response FIFO and in-flight limit are full.
2. **td (drained).** `ECALL` issues to the CSR pipe (`X_xfer`) and `csr_active` is set. In the same cycle (or earlier, if the CSR pipe is not ready, since `squash_sent` makes it fire only once) `squash_pub`
   fires with target `mtvec` base. Fetch redirects. `FetchUnitL3` adds every outstanding request, including the FIFO entries, to `num_to_squash` and drops them at one per cycle; new requests are limited by
   `num_in_flight + num_to_squash < p_max_in_flight`, and no instruction is delivered to decode until the stale ones are gone. `should_squash` for the `ECALL` itself stays false: a squash only affects
   instructions younger than its `seq_num`.
3. **td+1.** The CSR pipe drives `W` (no `rd` write) with `csr_cmd = ECALL`, and the commit unit latches the result and its `csr_*` fields into `X_reg`.
4. **td+2.** The instruction is inserted from `X_reg` into the ROB and, being the oldest, dequeued in the same cycle (bypass). `CSRNotif` fires and `CSRFile` writes `mepc`, `mcause`, `mtval` and
   `mstatus`. `csr_active` clears in the same cycle.
5. **td+3.** `F.rdy` reopens. The first handler instruction is in `F_reg` at `td+4` at the earliest and sees the updated CSRs. It usually arrives later: the stale entries drop at one per cycle (up to 8 if
   the FIFO filled while waiting) before the first handler instruction can be delivered, so the redirect overlaps the commit only partially. See section 10.

`MRET` is the same with `mepc` as the redirect target and only `mstatus` written. `EBREAK` differs from `ECALL` only in `mcause`.

## 7. Why this ordering is correct

- **Precision.** Older instructions have all committed before the trap op issues (back barrier), and nothing younger has entered (front barrier). The trap's CSR writes land at commit, so they are
  ordered after everything older.
- **`mtvec`/`mepc` in decode are current.** Two independent reasons: the trap op issues only when everything older has committed, and any older CSR or trap op held `F.rdy` low until it committed, so it
  could not even have reached decode before then. Only CSR-class ops write these CSRs, so the decode-time read is up to date.
- **Wrong path.** The redirect fires only after the drain, when nothing older is unresolved, so a wrong-path trap op can never redirect or write. Before the drain the trap op just waits, and
  `should_squash` kills it if an older branch turns out to be taken.
- **Handlers see their own writes.** Decode is held until the writes commit (`csr_active`), so handler `csrr` instructions read the updated `mepc`/`mcause`/`mscratch`.
- **ROB slot.** The trap op flows through the CSR pipe and inserts a normal ROB entry. If it did not, the ROB (indexed by `seq_num`, no gaps) would stall at its slot forever. The trapping
  instruction therefore appears in the commit trace with `wen = 0`.
- **1-bit `csr_active` is exact.** The argument in [CSR_DESIGN.md](CSR_DESIGN.md) ("Why the 1-bit clear is safe") applies unchanged, because the trap op has the same barriers.

## 8. Interactions with the CSR design

- A trap op **is** a CSR op for the barriers: no additional serialization logic.
- One writer and one interface: trap effects are new `cmd` values on the existing `CSRNotif`, not a second port.
- **CSR access checks are not part of this design.** Trapping on an unimplemented CSR or a write to a read-only CSR would need an illegal-instruction path, which is out of scope. Reads of unknown
  CSRs keep returning 0 and writes keep being ignored, as in [CSR_DESIGN.md](CSR_DESIGN.md).

## 9. Moving to late exceptions (future)

What stays: the trap `cmd` encodings, `CSRNotif` (with `pc`), the `CSRFile` trap logic, the trap CSR set, `CSRTrapIntf`, and the `X__WIntf`/ROB `csr_*` fields.

What changes:

- Exceptions detected after issue (load/store faults, etc.) are reported per instruction from the execute units. The `csr_*` fields are the natural carrier: an execute unit that currently ties
  them off could drive a trap `csr_cmd`. That needs a wider `cmd` (`100`-`110` are used, `111` is spare) and a way to carry `mtval`.
- The trap is taken when that instruction reaches commit. The commit unit (or `CSRFile`) publishes the redirect as a `SquashNotif`; `SquashUnitL1` gains a third input.
- **Squash has to reach everything past decode:** every execute pipe, the ROB, and `csr_active` must clear if a squash covers a CSR-class op. Today no unit past decode has a squash port, and
  `RenameTable` has no rollback on squash. The 1-bit `csr_active` argument in [CSR_DESIGN.md](CSR_DESIGN.md) would also need revisiting, because a late exception can squash a CSR-class op that is
  already in flight.
- Decode-side trap detection then only marks the exception (or is removed), and the decode-time redirect goes away.

## 10. Redirect latency (deferred)

**What the cost is.** The trap op waits in decode until everything older has committed (`td`), and only then fires the redirect. Meanwhile fetch has been running ahead down the sequential path, so its
8-entry response FIFO and its in-flight requests fill with instructions that the trap makes stale. When the redirect fires, `FetchUnitL3` counts all of those into `num_to_squash` and drops them at one per
cycle (`resp_pop`). It may send new requests as soon as `num_in_flight + num_to_squash < p_max_in_flight`, but `D.val` stays low until `num_to_squash == 0`, so no handler instruction reaches decode until
the stale ones are gone. Decode itself is ready again at `td+3`. So the handler's first instruction reaches decode roughly `up to 8 cycles + any remaining memory latency` after `td`, which can be several
cycles after decode could take it. The redirect overlaps the trap's commit only partially.

**The alternative.** Fire the redirect as soon as the trap op is in `F_reg`, without waiting for `drained`, the way `JAL`/`JALR` already redirect today. The stale entries then drop while decode is
still waiting for the drain, so the handler's first instruction would be waiting in the FIFO by `td+4`. The saving is up to the drop time (about 8 cycles) per trap, and only when the drain wait is long
enough to hide it; if the trap op arrives with nothing older in flight there is nothing to hide. The change is one term: drop `drained` from the trap redirect condition. The issue, the barriers and the
CSR writes are untouched.

**Why it is deferred.** It is not unsafe by itself, but it removes the arguments that make the drained redirect obviously correct:

- **Wrong path.** A trap op behind an unresolved older branch would redirect fetch before it is known to be on the correct path. Today this resolves the same way it does for `JAL`: the branch's squash
  arrives in the same cycle (branches resolve one cycle after issue) and `SquashUnitL1` picks the older one. That relies on the same timing coincidence as the rest of the design (nothing past
  decode is squashable). If an older squash ever arrived in a later cycle, fetch would be redirected twice; I expect the final target to be right because the older squash overrides, but it would then depend on
  ordering details that the drained redirect avoids entirely.
- **Late exceptions (future).** An older instruction that faults after the early redirect would have to override it, adding another ordering case.
- **`mtvec`/`mepc` are still current** with an early redirect (an older CSR or trap op holds `F.rdy` low until it commits), so that is not a concern.

**Impact in practice.** Traps (`ECALL`, `EBREAK`) are rare, so the extra latency only matters for trap-heavy code. Keeping the redirect at issue matches the decision to treat trap ops like CSR ops with
both barriers, for safety. Revisit with measurements if trap latency ever matters.

## 11. Decisions recorded and remaining items

Decided:

1. `mtval` is always 0.
2. The trapping instruction commits through the ROB and appears in the commit trace (`wen = 0`). The FL model has no trap support, so trace-compare tests cannot cover traps yet.
3. Only `ECALL`, `EBREAK` and `MRET` are added. `WFI` and `FENCE.I` are not.
4. `mscratch` is added as a plain read/write CSR.
5. Illegal instructions do not raise exceptions; decode keeps stalling on them as it does today. No `OP_ILLEGAL`.
6. The redirect selector is the widened 3-bit `jal`.
7. `mtvec` and `mepc` reach decode through a new interface file, `CSRTrapIntf`.
8. The redirect stays at issue, after the drain (section 10).
9. Nested traps and interrupts are out of scope. `MIE` is cleared on entry, but there are no interrupt sources.

Remaining:

- The name `CSRTrapIntf` is provisional.

## 12. Implementation order (after [CSR_DESIGN.md](CSR_DESIGN.md))

1. `ISA.v` `MRET`; `UArch.v` new uops and `num_ops`.
2. `InstRouter` entries for the new uops; `InstDecoder` entries (with `is_csr = 1`).
3. New `CSRTrapIntf`.
4. `CSRFile`: `mstatus`/`mscratch`/`mtvec`/`mepc`/`mcause`/`mtval`, trap `cmd` handling, `CSRTrapIntf` outputs. `CSRNotif` gains `pc`; the commit unit drives it from `rob_output.pc`.
5. CSR pipe: the three trap `cmd` arms.
6. Decode: widen `jal` to 3 bits, the redirect condition (fires on `drained`, not on `X_xfer`), the target mux, and the `CSRTrapIntf` input.

No tests are added or changed as part of this work. Top-level integration is out of scope, as in [CSR_DESIGN.md](CSR_DESIGN.md).
