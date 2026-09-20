# CSR Design: Barriered, Commit-Time CSR Updates

Status: final proposed design. No RTL has been changed. This document is the module-level spec.

Scope: the modules that implement CSR instructions (`CSRRW/S/C`, `CSRRWI/SI/CI`). Out of scope: top-level
integration and all tests (existing tests are intentionally left untouched; see "Known impacts").
[TRAP_DESIGN.md](TRAP_DESIGN.md) builds on this mechanism for `ECALL`/`EBREAK`/`MRET`; it predates this revision and
needs to be updated to match.

## 1. The rule

A CSR op has a barrier on both sides, its read happens after the older instructions have drained, and its write
happens at commit.

- **Front barrier:** nothing younger enters the pipeline from the moment the CSR is in decode until it commits.
- **Back barrier:** the CSR does not issue until every older instruction has committed.
- **Read:** in the CSR pipe, at execute, after the drain.
- **Write:** at commit, from the ROB entry, by the commit unit, through a new `CSRNotif` to a standalone `CSRFile`.

## 2. Background: how the pipeline works today

Pipeline: Fetch ([FetchUnitL3.v](hw/fetch/fetch_unit_variants/FetchUnitL3.v)) -> Decode/Issue with register renaming
(single-issue, one-entry `F_reg`) -> N parallel execute pipes -> Writeback/Commit
([WritebackCommitUnitL3.v](hw/writeback_commit/writeback_commit_unit_variants/WritebackCommitUnitL3.v)).

How a normal register write happens:

1. An execute unit drives `X__WIntf` (`val, seq_num, pc, waddr, wdata, wen, preg, ppreg`).
2. The writeback unit arbitrates between pipes by sequence number (`SeqArb`) and, in the same cycle, drives the `complete`
   notification. Decode's physical regfile is written from `complete`, and `RenameTable` clears the pending bit. This
   is out of order, and safe because renaming gives each in-flight destination its own physical register.
3. One cycle later the writeback unit inserts a ROB entry (`{pc, waddr, wdata, wen, ppreg}`) indexed by `seq_num`.
4. The ROB dequeues strictly in `seq_num` order and the unit broadcasts `CommitNotif`. Subscribers act on it: `RenameTable`
   frees the old physical register (`ppreg`), the instruction trace records the commit, `SeqAge` tracks the oldest in-flight
   sequence number, and fetch's sequence-number generator (`SeqNumGenL3`) frees the number for reuse.

The register file is therefore written at `complete`, and commit is bookkeeping only. Commit has no backpressure. Committed
sequence numbers are contiguous, because the ROB dequeues `deq_ptr` sequentially.

Squash: only decode (JAL/JALR) and `ControlFlowUnitL6` (taken branches, one cycle after issue) squash. No unit past decode has a
squash port. `SeqNumGenL3` rewinds to `squash.seq_num + 1` on a squash, so sequence numbers are reused.

## 3. Problems with the current CSR implementation

1. **The CSR file is written at execute.** [CSR.v](hw/execute/execute_units_l8/CSR.v) asserts `CSR.val = D_reg.val && W.rdy`, so
   [CSRFile.v](hw/execute/execute_units_l8/CSRFile.v) is mutated the cycle the instruction reaches execute. CSRs are not
   renamed: there is one architectural copy, so an early write cannot be undone and is visible to older in-flight instructions.
2. **No interlock.** Nothing stops a younger instruction from entering while a CSR is in flight, and nothing makes a CSR wait
   for older instructions.
3. **`zimm` is dropped.** `InstDecoder` produces `op1_sel` for the `*I` forms, but `DecodeIssueUnitL5` and
   `DecodeIssueUnitL5_sp26` ignore it (`op1 = rdata0`, and `raddr0 = x0` for the `*I` forms), so `op1` is always 0. Only
   [DecodeIssueUnitL6.v](hw/decode_issue/decode_issue_unit_variants/DecodeIssueUnitL6.v) has the mux (`op1 = {27'b0, inst[19:15]}`).
4. **`*I` forms are read-only in `CSR.v`.** `csr_cmd` maps only `OP_CSRRW/S/C`; the `*I` uops fall into `default` (read).
5. **`DecodeIssueUnitL6.v` is mislabeled.** Its module is still named `DecodeIssueUnitL5_sp26` and its include guard is
   still `..._DECODEISSUEUNITL5_V`. Including it with `DecodeIssueUnitL5_sp26.v` collides.
6. `CSRFile` implements only `fflags` (0x001), `frm` (0x002) and `fcsr` (0x003). Everything else reads 0 and ignores writes.

## 4. Design decisions

| # | Decision | Why |
|---|---|---|
| 1 | The CSR file is updated **at commit** | Standard practice for architectural state. CSRs are not renamed, so the update must not be visible before the instruction is guaranteed to retire in order. |
| 2 | **Front barrier** (`csr_active`) | At most one CSR is in flight, and nothing younger reads stale CSR state or writes it (CSR WAW). |
| 3 | **Back barrier**: the CSR waits in decode until it is the oldest instruction | The read then sees the effects of everything older (FP `fflags`, counters), and the CSR can never be squashed after issue. |
| 4 | The **read is at execute**, in the CSR pipe | After the drain the CSR is the only instruction in flight, so the read is correct with no extra check in the pipe. `rd` uses the normal `complete` path. |
| 5 | The write request **rides `X__WIntf` into the ROB entry** | It travels with the instruction (per-instruction, no separate record), the ROB is already parametric in message width, and it generalizes to trap ops. Area cost accepted. |
| 6 | `CSRFile` is a **standalone** unit with a single writer, the new **`CSRNotif`** from the commit unit | One access point, several possible readers, and it can be relocated later without touching the pipeline. |
| 7 | `is_csr` is a **decoder control signal**, used by the barriers; it is **not** passed down the pipeline | Nothing downstream needs it: the CSR pipe is dedicated, and `csr_cmd != 0` identifies an op that must write at commit. |
| 8 | `debug_stall` stays in decode | Orthogonal; it is ANDed into `F.rdy` as today. |

## 5. Behaviour and timeline

```
 Fetch -> [Decode L6] --(D__XIntf)--> [CSR pipe] --(X__WIntf + csr_* fields)--> [Commit unit L4]
             |  is_csr, drain wait          |  reads old value                       | SeqArb, ROB (csr_* in entry)
             |  csr_active                  v                                        |
             |                        [CSRFile: read port]                           | at dequeue, if csr_cmd != 0:
             +<------------------------ CommitNotif ---------------------------------+--> CSRNotif --> [CSRFile: write]
                 (clears csr_active on the next commit)
```

Life of a `CSRRW rd, csr, rs1`:

1. It reaches `F_reg`. `F.rdy` goes low immediately. It waits until every older instruction has committed.
2. **td:** drained, so it issues (`X_xfer`). `csr_active` is set.
3. **td+1:** the CSR pipe reads the old value and drives it on `W.wdata`. It also drives `csr_cmd/addr/wdata`. `complete` writes
   `rd`, and the instruction is inserted into the ROB.
4. **td+2:** the ROB dequeues it (bypass: it is the oldest). `CSRNotif` fires, `CSRFile` writes, and `csr_active` clears in the same cycle.
5. **td+3:** `F.rdy` reopens. The next instruction is in `F_reg` at td+4.

## 6. Component specifications

### 6.1 [InstDecoder.v](hw/decode_issue/InstDecoder.v)

- New output `is_csr`, a new column in the control-signal table (`cs()` gains an argument; every row gets the column).
- 1 for the six CSR ops, 0 for everything else including the `default` row. Trap ops set it to 1 later ([TRAP_DESIGN.md](TRAP_DESIGN.md)).

### 6.2 [DecodeIssueUnitL6.v](hw/decode_issue/decode_issue_unit_variants/DecodeIssueUnitL6.v)

- Rename the module to `DecodeIssueUnitL6` and the include guard to `..._DECODEISSUEUNITL6_V`. Update the header comment.
- Keep the existing `op1_sel` mux (`zimm` into `op1`) and `debug_stall`. No new ports (`commit` is already a port).
- `csr_class = F_reg.val & decoder_val & decoder_is_csr`.
- **Back barrier:** `drained = ( F_reg.seq_num == seq_age.oldest_seq_num )`. The router `val` gains a term:

  ```
  val = F_reg.val & !stall_pending & decoder_val & !should_squash & ( !decoder_is_csr | drained )
  ```

  While waiting, the CSR is still squashable by `should_squash`.
- **Front barrier:** new state `csr_active` (1 bit).
  - **Set** on `X_xfer & decoder_is_csr`.
  - **Clear** on `commit.val`. After issue the CSR is the only instruction in flight (section 7), so the next commit is its own.
  - Reset: `csr_active <= 0`.
- `F.rdy` becomes:

  ```
  F.rdy = ~debug_stall
        & ~csr_active
        & ~( csr_class & ~should_squash )
        & ( (X_xfer & !stall_pending & decoder_val) | should_squash | !F_reg.val )
  ```

  The combinational `csr_class` term is required. The existing `X_xfer` term opens `F.rdy` on the same edge the CSR leaves decode, one
  cycle before the registered `csr_active` is visible; without the term a younger instruction slips in. The `~should_squash` mask lets a CSR that
  is being squashed in `F_reg` be replaced.
- **Set on issue, not on "CSR is in decode".** A CSR killed by `should_squash` in `F_reg` never issues, so `csr_active` cannot get stuck.
- Set and clear cannot occur in the same cycle: the CSR reaches commit at least two cycles after `X_xfer`.
- For register forms, the normal pending-bit stall (`stall_pending`) still applies to `rs1`. The `*I` forms use `raddr0 = x0`.

### 6.3 [SeqAge.v](hw/util/SeqAge.v)

No change. Decode already instantiates `SeqAge` as `seq_age` (it calls `seq_age.is_older`), and it reads `seq_age.oldest_seq_num` through the same instance for the `drained`
check. `oldest_seq_num` (the last commit's sequence number plus one) equals the next number to commit. Because committed numbers are contiguous, the equality is exactly "everything older has
committed". This is a hierarchical read of an internal signal, the same style as the existing hierarchical call to `is_older`; if a synthesis flow rejects it, the fallback is to expose
`oldest_seq_num` as an output port.

### 6.4 [X__WIntf.v](intf/X__WIntf.v)

- Add, marked `// Added in v5`: `csr_cmd[2:0]`, `csr_addr[11:0]`, `csr_wdata[31:0]`.
- Extend `X_intf` (outputs) and `W_intf` (inputs), and add `lint_off UNDRIVEN` for the new fields, as `CompleteNotif` does for its added fields.
- `csr_cmd`: `000` none, `001` write, `010` set, `011` clear. `100`-`111` are reserved for trap ops.

### 6.5 Execute units and [ExQueue.v](hw/execute/ExQueue.v)

- Every execute unit that sits on `X__WIntf` in a design using the L4 commit unit must drive `csr_cmd`, `csr_addr` and `csr_wdata` to 0 (three
  assigns each): ALUL6, IterativeMulDivRemL7, LoadStoreUnitL7, ControlFlowUnitL6, and ALUF where used. `csr_cmd` must be driven, not left
  undriven; otherwise a non-CSR result puts X into the ROB entry and into `CSRNotif.val`.
- **`ExQueue` copies `X__WIntf` fields one by one** (its `msg_t`), so it does not forward the new fields. It should forward them by
  extending `msg_t` (47 more bits per queue entry), so it stays a transparent buffer. The alternative is to tie them off in `ExQueue`, which
  silently breaks if a CSR pipe is ever placed behind one.
- Older execute-unit variants used only by older tops do not need changes: the older commit units do not read the new fields.

### 6.6 [CSR.v](hw/execute/execute_units_l8/CSR.v)

Reduced to a read-and-forward unit. The `D_reg`/`W` handshake, `D.rdy`, and the `W.wen/pc/seq_num/waddr/preg/ppreg` assignments are unchanged.

- Reads the old value through the read-only `CSRIntf` (`CSR.addr = D_reg.op2[11:0]`) and drives it on `W.wdata`.
- Maps all six uops to `csr_cmd`: `OP_CSRRW/WI -> 001`, `OP_CSRRS/SI -> 010`, `OP_CSRRC/CI -> 011`. This fixes the `*I` bug.
- Drives `W.csr_cmd`, `W.csr_addr = D_reg.op2[11:0]`, `W.csr_wdata = D_reg.op1`.
- **Does not write `CSRFile`.**
- It does not check that the pipeline is drained; it relies on decode's back barrier.

### 6.7 [CSRIntf.v](intf/CSRIntf.v)

Reduced to a read-only port: `addr` in, `rdata` out (combinational, the current architectural value). `val`, `rdy`, `wdata` and `cmd`
are removed; writes arrive only through `CSRNotif`. Modports stay `X_intf` (execute side) and `F_intf` (file side).

### 6.8 New interface `CSRNotif` (`intf/CSRNotif.v`)

Follows the existing `pub`/`sub` convention (see [CommitNotif.v](intf/CommitNotif.v)).

| Field | Width | Meaning |
|---|---|---|
| `val` | 1 | An operation is applied this cycle |
| `cmd` | 3 | `001` write, `010` set, `011` clear (`100`-`111` reserved for trap ops) |
| `addr` | 12 | CSR address |
| `wdata` | 32 | Operand (`rs1` value or `zimm`) |

Publisher: the commit unit. Subscriber: `CSRFile`. Fields such as `pc` are added later with the repo's "added in vN" convention.

### 6.9 [CSRFile.v](hw/execute/execute_units_l8/CSRFile.v)

- Ports: `CSRIntf.F_intf csr` (read-only) and `CSRNotif.sub csr_notif`.
- The existing write/set/clear logic for `fflags`, `frm` and `fcsr` moves onto `csr_notif` and applies combinationally on `csr_notif.val` (the
  register updates at the end of that cycle). `csr.rdy` goes away with the write path.
- The read path stays combinational on `csr.addr`.

### 6.10 New `WritebackCommitUnitL4.v` (copy of [WritebackCommitUnitL3.v](hw/writeback_commit/writeback_commit_unit_variants/WritebackCommitUnitL3.v))

- New port `CSRNotif.pub csr_notif`.
- Unpack `csr_cmd/addr/wdata` per pipe, mask them with `Ex_gnt`, and OR-reduce them into `_sel` signals, in both the `SYNTHESIS` and non-`SYNTHESIS`
  branches, exactly like the existing fields.
- Widen `X_input` (reset to 0 and default 0 in `X_reg_next`) and `t_rob_msg` (`csr_cmd`, `csr_addr`, `csr_wdata`), and assign `rob_input`.
  [ROB.v](hw/writeback_commit/ROB.v) is unchanged: it is parametric in `p_msg_bits`, which comes from `$bits(t_rob_msg)`.
- At dequeue: `csr_notif.val = commit.val & (rob_output.csr_cmd != 0)`; `cmd/addr/wdata` come from `rob_output`. The ROB bypass path is
  covered by `rob_output`.
- `complete`, `commit`, `SeqArb` and the trace are unchanged.
- `csr_notif.val` inherits the combinational path from ROB dequeue to the `CSRFile` write enable.

### 6.11 Unchanged

`ROB.v`, `SeqAge`, `CommitNotif`, `CompleteNotif`, `SeqArb`, `D__XIntf`, `RenameTable`, and all tests.

## 7. Invariants

1. **At issue, the CSR is the oldest instruction and nothing younger has entered.** So it is the only instruction in flight when it reads.
2. **CSR state is stable from the CSR's issue until its own commit.** Only CSR ops write the file and they are serialized, so the read at execute
   cannot race a write, and it can be held across `W` backpressure safely.
3. **Visibility.** The `CSRFile` write and the `csr_active` clear both happen in the CSR's commit cycle `t`. `F.rdy` reopens at `t+1` at the
   earliest, so any younger instruction is in `F_reg` at `t+2` or later and sees the new state. This requires `CSRFile` to apply `CSRNotif`
   combinationally; if a registered hop is ever added, `csr_active` must clear a cycle later or reads need a bypass.
4. **After the CSR issues, the next `commit.val` is the CSR's own.** See "Why the 1-bit clear is safe" below.
5. **No stale requests.** The request is stored in the ROB entry, which is cleared on dequeue, so it cannot outlive its instruction or match a
   reused sequence number.
6. **The CSR cannot be squashed after issue.** It issues only when nothing older is unresolved, so nothing can squash it.

### Why the 1-bit clear is safe

`csr_active` is set at the end of the issue cycle `td` and clears on the next `commit.val`. That is exact if the first commit after `td` is the CSR's own.

1. **No older commit at or after `td`.** `drained` at `td` means every older instruction has committed. `oldest_seq_num` is a register updated at the edge after a
   commit, so the last older commit happened in a cycle before `td`.
2. **No younger commit.** No younger instruction can be in the pipeline: `F.rdy` is held low by the combinational `csr_class` term from the moment the CSR is
   in `F_reg`, and by `csr_active` afterwards, so nothing younger is accepted until the barrier clears.
3. **The CSR cannot commit before `td+2`.** `commit.val` needs a valid ROB entry at `deq_ptr` (or an insert in the same cycle). The CSR's entry is inserted
   from `X_reg` at `td+2` at the earliest, and `deq_ptr` already points at the CSR's slot, so nothing else can dequeue.
4. **Nothing can squash it in between.** With nothing older or younger in flight, no unit can raise a squash while `csr_active` is set.

The load-bearing assumption is (1): the `drained` check must mean exactly "every older instruction has committed". That holds because committed sequence numbers are
contiguous (the ROB dequeues `deq_ptr` sequentially) and `oldest_seq_num` tracks the last commit plus one. If `drained` were ever wrong, an older commit would release
the barrier early, and nothing else would catch it.

## 8. Hazards covered

| Hazard | Covered by |
|---|---|
| Younger instruction reads stale CSR state, or a younger CSR writes before this one (CSR WAW) | Front barrier |
| Older instruction with a commit-time CSR effect (FP `fflags` accrual, counters) not yet visible to this CSR's read | Back barrier: the read is after everything older has committed |
| A future older instruction that reads a CSR sees the new value | The write is at commit, after it has committed |
| CSR write on a squashed or wrong-path instruction | Back barrier plus commit-time write: it issues only when non-speculative |
| CSR retained in `F_reg` and squashed | `csr_active` is set on issue, so a killed CSR never sets it |

## 9. Behaviour details

- **`rd` and the regfile.** The old CSR value reaches `rd` at `complete`, before commit. This is safe: it goes to a fresh physical register, and the CSR cannot
  be squashed. `rd = x0` behaves as for any instruction (`W.wen = 0`).
- **Unknown CSR addresses.** Reads return 0 and writes are ignored (unchanged). Trapping on these is future work.
- **Spec no-write rules.** `CSRRS/C` with `rs1 == x0` or `zimm == 0` must not write, and `CSRRW` with `rd == x0` must not read. Ignored today (harmless with
  `fflags/frm`). Decode could later encode `csr_cmd = 000` for these, since it sees the `rs1` index.
- **Performance.** Each CSR costs a full drain, then about 3 cycles to commit before younger instructions can enter. Fetch keeps prefetching into its response FIFO
  while decode is held.
- **Trap ops.** `ECALL`/`EBREAK`/`MRET` are CSR-class ops with the same barriers and the same `X__WIntf` and ROB fields (`pc` is already in the entry, the `mtval` operand
  rides `csr_wdata`, and the trap encodings use the reserved `csr_cmd` values). Their redirect fires at issue, after the drain.

## 10. Costs

- **Area:** 47 bits (`csr_cmd` 3 + `csr_addr` 12 + `csr_wdata` 32) in each of the 32 ROB entries, in `X_reg`, and in each `ExQueue` entry, roughly 1.6 kbit of flops plus a wider
  dequeue mux. Accepted for now.
- **Timing:** the combinational path from ROB dequeue to the `CSRFile` write enable.
- **Latency:** the drain plus about 3 cycles per CSR.
- **Trust:** the CSR pipe relies on decode's drain and does not check it.

## 11. Alternatives considered

| Alternative | Why not |
|---|---|
| **Write at execute** (today) | Not committable, not squash-safe, visible to older instructions. |
| **Hold the CSR in the CSR pipe until it is oldest** (instead of in decode) | Puts a `commit` port and comparator in `CSR.v` and lets a CSR sit past decode with older instructions unresolved, so the timing-based "issued instructions cannot be squashed" invariant applies. |
| **Read at commit, with a late `complete` for `rd`** | The most invasive: a mux on `complete`, overrides of `commit.wdata/wen`, suppressing the early `complete`, and the commit unit as `CSRIntf` requester. The CSR pipe would become a pass-through. Possible future direction. |
| **Decode-owned:** decode reads `CSRFile` and applies the write on commit match, `rd` via an ALU move, no CSR unit | Smallest change now, but decode owns architectural CSR state and it has to be moved out when exceptions move to commit. |
| **Single request record in the commit unit** (fed by a sideband from the CSR pipe or a decode-to-commit notification) | About 1.5 kbit less area than storing the request in the ROB, but it depends on one-CSR-in-flight and adds either a pipe-specific port or another interface. Storing it in the ROB was chosen for uniformity. Worth revisiting if area matters. |
| **Reuse existing `X__WIntf`/ROB fields for the request** | Every field is live for a CSR: `wdata` carries the old value to `rd` and to the trace, while the operand is live at the same time; `pc`, `waddr`, `wen`, `ppreg`, `preg` and `seq_num` are all needed. A partial reuse (operand in the ROB `wdata` slot, with the old value re-read from `CSRFile` at commit for the trace) would save about 32 bits per ROB entry but does not reduce the `X__WIntf` wires, and adds a `CSRFile` read at commit. |
| **Drain-then-issue in the execute stage** (CSR executes early because "the pipeline is drained") | The write would still happen in execute, not at commit. Rejected in favour of commit-time writes. |

## 12. Known impacts

- [CSRL8_test.v](hw/execute/test/l8/CSRL8_test.v) will stop building or passing once `CSR.v` stops writing and `CSRIntf` becomes read-only. It is intentionally left
  unchanged; someone will need to update it separately.
- The assembler ([asm/inst.h](asm/inst.h)) has `csrrw/csrrs/csrrc` but no `*I` forms, and the FL model ([fl/](fl/)) has no CSR support, so top-level trace-compare tests
  cannot cover CSRs yet.
- `num_ops` in [UArch.v](defs/UArch.v) is 44 and full. This design adds no uops, but [TRAP_DESIGN.md](TRAP_DESIGN.md) does.
- Older tops and their execute units are functionally unaffected, because the older commit units do not read the new fields.

## 13. Implementation order (modules only, no tests)

1. `CSRNotif`.
2. `CSRIntf` (read-only) and `CSRFile` (write via `CSRNotif`).
3. `X__WIntf` v5 fields; execute-unit tie-offs; `ExQueue` forwarding.
4. `CSR.v`.
5. `WritebackCommitUnitL4`.
6. `InstDecoder.is_csr`; `DecodeIssueUnitL6` (rename, barriers).

## 14. Out of scope

Top-level integration (a CSR pipe with `OP_CSRR*_VEC` in a top's pipe subsets, a `CSRFile` instance, and using the L4 and L6 units) and all tests. Without a pipe
claiming the CSR uops, decode hangs on the first CSR instruction in any top that includes the L6 unit.
