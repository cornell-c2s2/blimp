# Store Queue Design: Commit-Time Stores with Store-to-Load Forwarding

Status: design approved, not implemented.

## 1. Summary

Stores stop writing memory from the LSU. Each store is buffered in a **store queue (SQ)** from decode until it commits, then in a
**completed store buffer (CSB)** until its write is acknowledged by memory. Loads search both structures and forward the youngest older
store data byte by byte, merging with memory when a load is only partly covered.

This is a step toward late-commit exceptions: once execute units can be squashed (a teammate's work, section 8), no store younger than
an excepting instruction ever reaches memory, and no committed store is lost.

**In scope:** `StoreQueue`, `CompletedStoreBuffer` (with the retire stage), their search logic, `WritebackCommitUnitL5`,
`LoadStoreUnitL9`, `DecodeIssueUnitL7`, the `InstDecoder` `store` column, and the interfaces between them.

**Out of scope:** the top level, tests, squash handling in execute units, rename recovery and ROB squash mechanics (section 8),
exception producers, FENCE (stays a no-op), and MMIO side effects (section 9). The design is not functional on its own: it is correct
once the section 8 dependencies and the section 11 top-level requirements are met.

## 2. Terms

| Term | Meaning |
|---|---|
| Lane | One of the 4 bytes of a 32-bit memory word, selected by `addr[1:0]` |
| `strb` | 4-bit lane mask of an access: `base_strb << addr[1:0]`, with `base_strb` = `0001` (B), `0011` (H), `1111` (W) |
| Lane-aligned data | Store data shifted into its lanes: `rs2 << (8 * addr[1:0])`. Memory messages already use this format |
| Word address | `addr[31:2]`. All memory requests are word-aligned |
| Filled | An SQ entry whose address, `strb` and data have been written by the LSU |
| Youngest | Latest in program order. In a circular buffer, the valid entry nearest before `tail` |
| Pointer arithmetic | `head`, `tail` and every `+1` / `-1` on them wrap modulo the structure's depth, as in [ROB.v](hw/writeback_commit/ROB.v), so a depth need not be a power of 2 |
| Older / younger | Program order, decided by `SeqAge.is_older`, which handles sequence-number wraparound |
| Speculative store | A store that has not committed: lives in the SQ |
| Completed store | A store that has committed but whose write is not yet acknowledged: lives in the CSB |
| Retire | Sending the CSB head's write to memory and dequeuing it when the write is acknowledged |

## 3. Overview

```
  DecodeIssueUnitL7 ---- StoreQueueIntf (alloc) -------------+
        |                                                    |    inside WritebackCommitUnitL5
        | D__XIntf (+ sq_idx)                                v
        v                                             [ StoreQueue ] <---- SquashNotif
  LoadStoreUnitL9 ------ StoreQueueIntf (fill, search) ---->  |
        |                                                    |  dequeue when ROB head seq == SQ head seq
        |                                                    v
        +------ CompletedStoreBufferIntf (search) ---> [ CompletedStoreBuffer ] -- retire: MemIntf store_mem --> data memory
        |
        +------ MemIntf mem (reads only) ------------------------------------------------------------------> data memory
```

Life of a store and a load:

| Stage | Store | Load |
|---|---|---|
| D (decode) | Allocates `sq[tail]` at issue, recording its `seq_num`. Stalls if the SQ is full. Sends `sq_idx` with the instruction | - |
| X stage 1 | Fills `sq[sq_idx]` with word address, `strb` and lane-aligned data. No memory request | Searches the SQ and the CSB. All needed lanes covered: forward, no memory request. Some covered: memory request, forwarded lanes carried along. None: memory request |
| X stage 2 | Passes to W with `wen = 0` | Merges forwarded lanes over the memory response (if any), then shifts and extends as today |
| C (commit) | When the ROB head is the SQ head, the store moves from the SQ to the CSB. Commit stalls if the CSB cannot accept it | Commits normally |
| R (retire) | The CSB head is written to memory; it is dequeued when the write is acknowledged | - |

All new state (SQ, CSB, retire) lives in `WritebackCommitUnitL5`. The LSU reaches it through two interfaces, one per structure.

## 4. Interfaces

### 4.1 `StoreQueueIntf` (new, `intf/StoreQueueIntf.v`)

Parameters: `p_seq_num_bits = 5`, `p_sq_idx_bits = 2`.

| Group | Signal | Width | Driven by | Meaning |
|---|---|---|---|---|
| Allocate | `alloc_val` | 1 | decode | Allocate an entry for the store issuing this cycle |
| | `alloc_seq_num` | `p_seq_num_bits` | decode | Sequence number of that store |
| | `alloc_rdy` | 1 | SQ | An entry is available this cycle |
| | `alloc_idx` | `p_sq_idx_bits` | SQ | Index of the entry being allocated (`tail`) |
| Fill | `fill_val` | 1 | LSU | Write the store's address and data this cycle |
| | `fill_idx` | `p_sq_idx_bits` | LSU | Entry to fill (the store's `sq_idx`) |
| | `fill_addr` | 30 (`[31:2]`) | LSU | Word address |
| | `fill_strb` | 4 | LSU | Lanes written |
| | `fill_data` | 32 | LSU | Lane-aligned data |
| Search | `search_addr` | 30 (`[31:2]`) | LSU | Word address of the load in stage 1 |
| | `search_hit` | 4 | SQ | Per lane: some filled entry for this word writes the lane |
| | `search_data` | 32 | SQ | Per lane: that lane's byte from the youngest such entry |

Modports: `D_intf` (decode: drives `alloc_val` and `alloc_seq_num`), `X_intf` (LSU: drives the fill group and `search_addr`),
`SQ_intf` (commit unit: drives `alloc_rdy`, `alloc_idx`, `search_hit` and `search_data`).

`p_sq_idx_bits` here and in `D__XIntf` (4.3) must equal `$clog2` of the commit unit's `p_sq_depth`; the commit unit checks this at
elaboration.

### 4.2 `CompletedStoreBufferIntf` (new, `intf/CompletedStoreBufferIntf.v`)

| Signal | Width | Driven by | Meaning |
|---|---|---|---|
| `search_addr` | 30 (`[31:2]`) | LSU | Word address of the load in stage 1 |
| `search_hit` | 4 | CSB | Per lane: some entry for this word writes the lane |
| `search_data` | 32 | CSB | Per lane: that lane's byte from the youngest such entry |

Modports: `X_intf` (LSU), `CSB_intf` (commit unit).

### 4.3 `D__XIntf` (changed in place)

Adds parameter `p_sq_idx_bits = 2` and signal `sq_idx [p_sq_idx_bits-1:0]` (`D_intf` output, `X_intf` input): the SQ entry of a
store, from `alloc_idx`. Only meaningful for stores. Placed inside the existing `lint_off UNUSEDSIGNAL` region and wrapped in
`lint_off UNDRIVEN`, as `X__WIntf` does for its v5 fields, because older decode units do not drive it and non-memory units do not read it.

### 4.4 Unchanged

`X__WIntf`, `CompleteNotif`, `CommitNotif`, `SquashNotif`, `CSRNotif`, `MemIntf`.

## 5. Components

### 5.1 `CircularPriorityEncoder` (new, `hw/writeback_commit/CircularPriorityEncoder.v`)

Parameters `p_width` and `p_ptr_bits`. Inputs `in [p_width-1:0]` and `ptr`. Output `out`, one-hot: the set bit of `in` found first when searching
downward from `ptr - 1`, wrapping around (`ptr - 1`, `ptr - 2`, ..., `ptr`). With `ptr = tail`, this selects the youngest entry.

Implemented as a priority chain over `ptr - 1 - k` (wrapped) for `k = 0 .. p_width-1`, which handles any `p_width`.

### 5.2 `StoreBufferSearch` (new, `hw/writeback_commit/StoreBufferSearch.v`)

Shared by the SQ and CSB. Parameter `p_depth`. Inputs: per-entry `eligible`, `addr [31:2]`, `strb`, `data`; `tail`; `search_addr`.
Outputs `hit [3:0]`, `data [31:0]`.

For each lane L:

- `match_L[i] = eligible[i] & ( addr[i] == search_addr ) & strb[i][L]` (the address compare is shared across lanes)
- `sel_L = CircularPriorityEncoder( match_L, tail )`
- `hit[L] = |match_L`, `data[8L+7:8L]` = byte L of the entry selected by `sel_L`

### 5.3 `StoreQueue` (new, `hw/writeback_commit/StoreQueue.v`)

Holds speculative stores in program order.

**Parameters:** `p_depth = 4`, `p_seq_num_bits = 5` (needed for the plain dequeue ports). Both are checked against `StoreQueueIntf` at elaboration.

**Ports:** `clk`, `rst`, `StoreQueueIntf.SQ_intf sq`, `SquashNotif.sub squash`, `CommitNotif.sub commit` (feeds an internal `SeqAge`),
and plain dequeue ports `deq_en` (in), `deq_rdy`, `deq_seq_num`, `deq_addr`, `deq_strb`, `deq_data` (out).

**State:** per entry `val`, `filled`, `seq_num`, `addr [31:2]`, `strb`, `data`; pointers `head` (oldest) and `tail` (next free).
`full = val[tail]`, `empty = !val[head]` (per-entry valid bits keep this unambiguous after a squash).

**Operations:**

| Operation | Behaviour |
|---|---|
| Allocate | `alloc_rdy = !full \| deq_en`. On `alloc_val & alloc_rdy`: `sq[tail] <= {val 1, filled 0, seq_num alloc_seq_num}`, `tail++`. `alloc_idx = tail` |
| Fill | On `fill_val`, if `sq[fill_idx]` is valid: write its `addr`, `strb`, `data` and set `filled` |
| Search | `StoreBufferSearch` with `eligible = val & filled`, `ptr = tail` |
| Dequeue | `deq_rdy = val[head] & filled[head]`; `deq_*` present the head. On `deq_en`: clear `val[head]`, `head++` |
| Squash | On `squash.val`: clear `val` of every valid entry with `seq_age.is_older( squash.seq_num, seq_num )`. These form a contiguous youngest suffix (I1); `tail` moves to the oldest removed entry, or is unchanged if none is removed |

**Same-cycle rules:**

| Same cycle | Result |
|---|---|
| Squash + allocate | Squash wins; the allocation is dropped. Never discards a live store: the instruction in decode is younger than any squash source, and decode already withholds `alloc_val` on `should_squash` |
| Squash + fill | The fill is dropped if its entry is removed this cycle. A squashed store filling in a later cycle is excluded by D1 |
| Squash + dequeue | Both apply. The head being dequeued is never removed (I7) |
| Allocate + dequeue | Independent. When full, `tail == head`: the dequeue frees the slot and the allocation's write wins |
| Fill + search | Cannot coincide: both come from LSU stage 1, which holds one instruction |
| Search + dequeue | The search sees the entry; next cycle it is in the CSB (I5) |

### 5.4 `CompletedStoreBuffer` (new, `hw/writeback_commit/CompletedStoreBuffer.v`)

Holds committed stores in commit order and retires them to memory. Never squashed.

**Parameters:** `p_depth = 4`, `p_opaq_bits = 8` (must match `MemIntf`).

**Ports:** `clk`, `rst`, `CompletedStoreBufferIntf.CSB_intf csb`, `MemIntf.client mem` (the retire client), and plain push ports
`push_en`, `push_addr`, `push_strb`, `push_data` (in), `push_rdy` (out).

**State:** per entry `val`, `addr [31:2]`, `strb`, `data`; `head`, `tail`; `sent` (the head's write is outstanding).

**Operations:**

| Operation | Behaviour |
|---|---|
| Push | `push_rdy = !full \| pop`. On `push_en`: write `csb[tail]`, `tail++`. When full, `tail == head`: the pop frees the slot and the push's write wins |
| Send | `mem.req_val = !sent & ( val[head] \| push_en )`. Request: `op = MEM_MSG_WRITE`, `addr = {addr, 2'b00}`, `strb`, `data`, `opaque = 0`. When the CSB is empty, the request is taken from the push inputs (the store is sent in the cycle it arrives). On acceptance, `sent <= 1` |
| Ack and pop | `mem.resp_rdy = 1`. `pop = sent & mem.resp_val`. On `pop`: clear `val[head]`, `head++`, `sent <= 0`. The next send starts the following cycle |
| Search | `StoreBufferSearch` with `eligible = val`, `ptr = tail`. Entries stay searchable while their write is outstanding |

At most one write is outstanding. Starting the next send in the ack cycle is deliberately not bypassed: it would make `mem.req_val`
functionally depend on `mem.resp_val`. A structural path remains (`resp_val` to `pop`, `push_rdy`, the commit unit's `push_en`, then
`req_val`), but it is false: `pop` requires `sent`, and `sent` forces `req_val` low.

### 5.5 `WritebackCommitUnitL5` (copy of `WritebackCommitUnitL4`)

**New parameters:** `p_sq_depth = 4`, `p_csb_depth = 4`, `p_opaq_bits = 8` (for `store_mem`).

**New ports:** `SquashNotif.sub squash`, `StoreQueueIntf.SQ_intf sq`, `CompletedStoreBufferIntf.CSB_intf csb`, `MemIntf.client store_mem`.

**Internals:**

- Instantiates `StoreQueue` (with `sq`, `squash`) and `CompletedStoreBuffer` (with `csb`, `store_mem`).
- The existing private `CommitNotif` instance that feeds `SeqArb` (`arb_commit` in L4) is renamed `local_commit` and also passed to the
  SQ as its `commit` port. The unit cannot pass its own `CommitNotif.pub` port to a subscriber, so it mirrors its commit signals into an
  instance it owns; L4 already does this for `SeqArb`.
- Commit, replacing L4's `deq_en = deq_rdy = commit.val`:

  ```systemverilog
  head_is_store   = sq_deq_rdy & ( sq_deq_seq_num == rob_deq_idx );
  commit_ok       = rob_deq_rdy & ( !head_is_store | csb_push_rdy );
  commit.val      = commit_ok;                       // also rob.deq_en
  sq_deq_en       = commit_ok & head_is_store;
  csb_push_en     = sq_deq_en & !rob_output.exc_val; // an excepting store is dropped (I9)
  ```

  Commit stalls only when the head is a store and the CSB cannot take it, including an excepting store (decision 12).
- `csr_notif` and `complete` are unchanged; `csr_notif.val` already derives from `commit.val`.

### 5.6 `LoadStoreUnitL9` (copy of `LoadStoreUnitL7`, in `execute_units_l9/`)

**New ports:** `StoreQueueIntf.X_intf sq`, `CompletedStoreBufferIntf.X_intf csb`. `D_reg` gains `sq_idx`. The existing `mem` port
now only issues reads.

**Stage 1** (address, lanes and shifted data computed as today):

- Store: `sq.fill_val = D_reg.val & is_store & stage2_push`, with `fill_idx = D_reg.sq_idx`, the word address, `strb` and shifted data.
  No memory request.
- Load: `sq.search_addr = csb.search_addr = addr[31:2]`. Per lane, the SQ result takes priority over the CSB result (I1):
  `hit = sq.search_hit | csb.search_hit`, `fwd_data[L] = sq.search_hit[L] ? sq byte L : csb byte L`.
  `fwd_cover = hit & strb`; `need_mem = is_load & ( fwd_cover != strb )`.
- `mem.req_val = D_reg.val & need_mem & stage2_rdy`; `op = MEM_MSG_READ`.
- `stage2_push = D_reg.val & stage2_rdy & ( !need_mem | mem.req_rdy )`; `D.rdy = !D_reg.val | stage2_push`.
  (L7 computes `stage2_push` without `stage2_rdy`, so with a full FIFO and `mem.req_rdy` high it pushes, overwriting the FIFO head, and
  clears `D_reg` without sending a request. L9 must include `stage2_rdy`.)

**In-flight FIFO entry** gains `resp` (a memory response is expected), `fwd_mask [3:0]` (`fwd_cover`; 0 for stores) and `fwd_data [31:0]`.

**Stage 2:**

- `W.val = stage2_reg.val & ( !resp | mem.resp_val )`; `mem.resp_rdy = stage2_reg.val & resp & W.rdy`.
- Word = per lane `fwd_mask[L] ? fwd_data[L] : mem.resp_msg.data[L]`, then the existing shift and sign or zero extension. When
  `!resp`, every lane the load reads is forwarded; the other lanes are don't-care.
- Pop when `W` transfers or `stage2_reg` is empty, as today.
- Stores: `W.wen = 0` as today.

Squash handling in this unit is section 8 (D1, D2).

### 5.7 `DecodeIssueUnitL7` (copy of `DecodeIssueUnitL6`)

**New port:** `StoreQueueIntf.D_intf sq`.

- `stall_pending |= decoder_store & !sq.alloc_rdy`.
- `sq.alloc_val = X_xfer & decoder_store & !should_squash`, `sq.alloc_seq_num = F_reg.seq_num` (the same gating as rename allocation).
- `Ex[k].sq_idx = sq.alloc_idx`.

### 5.8 `InstDecoder` (changed in place)

New column and output `store` (`cs_store` in the `cs` task): `y` for `SB`, `SH`, `SW`; `n` for every other row, including `default`, so it
is never `x`. Older decode units instantiate the decoder with named ports and leave `store` unconnected.

## 6. Correctness

### 6.1 Invariants

| # | Invariant | Why it holds |
|---|---|---|
| I1 | SQ entries are in program order, CSB entries in commit order, and every SQ entry is younger than every CSB entry | Decode issues in order and allocates in order; commit is in order and moves only the SQ head to the CSB tail |
| I2 | At search time, every filled SQ entry is older than the searching load, and every unfilled one is younger | All loads and stores go to one in-order LSU (T1), and a store fills in the cycle it leaves stage 1, so every older store has filled before the load enters stage 1, and no younger store has |
| I3 | Every store fills its SQ entry before it completes, so the SQ head is filled when its store commits | The fill happens in stage 1, before W. **Future exception producers in the LSU must preserve this, including for a faulting store** |
| I4 | At commit, the ROB head is a store exactly when its `seq_num` equals the SQ head's | Sequence numbers are unique among in-flight instructions; SQ entries are removed in the squash cycle or popped at commit, so none holds a stale number (relies on D3, D4) |
| I5 | Until its write is acknowledged, every older store is visible to a load's search in exactly one structure | The SQ-to-CSB move happens on one clock edge; CSB entries stay searchable until their ack |
| I6 | Memory receives only committed stores, in program order | Only the CSB writes, in FIFO order, one write at a time, after commit |
| I7 | A squash never removes the entry being dequeued | The dequeued entry belongs to the committing instruction, the oldest in flight; a squash removes only instructions younger than an in-flight instruction |
| I8 | A load receives the correct value | Covered lanes come from the youngest older store (I1, I2, I5). An uncovered lane has no older store left in either structure, so every older store to it has been acknowledged, and by T2 the load's later read observes it. No younger store can write first: it commits only after the load, which commits only after its response. A load that forwarded from a store later squashed is younger than that store, so it is squashed too |
| I9 | An excepting store never reaches memory | Its entry survives its own squash (`is_older(x, x) = 0`) and is popped at commit without a CSB push |
| I10 | The design adds no combinational loop | `SeqAge` inside the SQ reads `commit.val` only into a register. `alloc_rdy` and `push_rdy` depend on dequeue and pop, never on allocate or push. SQ outputs used by commit (`deq_rdy`, `deq_seq_num`) and search outputs come from registered state only |
| I11 | No deadlock | A full SQ stalls decode; its head is filled (I3) and commits once it reaches the ROB head; that needs CSB space, which retire frees independently of the core. Once commit stalls, fetch runs out of sequence numbers and the LSU's loads drain, so retire gets the memory port even if loads have priority (T4). LSU writeback never waits on commit |

### 6.2 Late exceptions, once section 8 is in place

| Scenario | SQ | CSB | Memory |
|---|---|---|---|
| A load at seq 5 traps at commit; stores at seq 3 and 8 are buffered | Seq 3 moves to the CSB at its commit; seq 5's squash removes seq 8 | Seq 3 retires | Seq 3 written, seq 8 never: precise |
| A store at seq 5 traps at commit | Survives its own squash; popped and dropped at commit | - | Never written (I9) |
| A branch at seq 5 squashes from execute | Entries younger than seq 5 removed, filled or not | Untouched | Only committed stores are written |
| The trap handler loads an address with a committed store still in the CSB | - | Forwards to the load | Correct before the write lands |

## 7. Decisions

| # | Decision | Rejected alternatives | Why |
|---|---|---|---|
| 1 | Separate SQ and CSB | One buffer with a commit pointer | Clear split between speculative and committed state; retire only reads the CSB head |
| 2 | Allocate in decode, fill in LSU stage 1 | Fill at W, alongside the ROB write | A fill at W leaves a window in which a younger load cannot see an older store (it waits for its W grant); closing it needs an unknown-address stall or searching every in-flight copy |
| 3 | Commit identifies a store by `seq_num` match with the SQ head | `is_store` bit in the ROB entry | No `X__WIntf` or ROB change |
| 4 | Commit stalls when the head is a store and the CSB is full | No backpressure | The CSB is a separate fixed-size structure; the store must wait somewhere |
| 5 | Squash by `seq_num` and `is_older`, from `SquashNotif` | Flush the whole SQ; index snapshots on every instruction | A branch squash must keep older uncommitted stores; snapshots need a field on every instruction and ROB entry |
| 6 | Age reference from a private `CommitNotif` instance in the commit unit | A second top-level `CommitNotif.sub` port; a duplicated age register | Reuses `SeqAge` unchanged with no top-level change; L4 already does this for `SeqArb` |
| 7 | Per-lane search output | Youngest whole entry | Supports combining stores of different sizes and merging with memory |
| 8 | Forward always; merge with memory on partial cover; skip memory on full cover | A stall-on-match phase; stall on partial cover | The merge removes the stall path entirely; a fully forwarded load needs no memory round trip |
| 9 | Separate SQ and CSB search results, merged in the LSU | Merge inside the commit unit | The CSB can later move out of the commit unit unchanged; the merge is a fixed priority by I1 |
| 10 | Bypassed readiness: `alloc_rdy = !full \| deq_en`, `push_rdy = !full \| pop`; a store pushed into an empty CSB is sent in the same cycle | Registered `!full` | No bubbles when the structures are full; costs the long paths in section 10 |
| 11 | Free a CSB entry on ack, one write in flight | Free on send; several writes in flight | Free on send is correct only if every memory client shares one ordered path, which the 2-port test server does not provide |
| 12 | One uniform commit stall rule, even for an excepting store | Ignore `csb_rdy` for an excepting head | Exceptions are rare; one rule is simpler |
| 13 | Retire has its own memory client | Route writes through the LSU's port | Keeps the LSU's port read-only; priority between clients belongs to the memory crossbar |
| 14 | Plain ports inside the commit unit, interfaces between units | Interfaces everywhere | The commit unit drives dequeue and push itself; through an interface port whose modport makes those signals inputs to it, it could not |
| 15 | `p_depth = 4` for both structures, as parameters | - | - |

## 8. Dependencies on squash handling (teammate)

This design assumes the following from the squash, ROB and rename work. Each item states what is required and why.

| # | Requirement | Area | Why |
|---|---|---|---|
| D1 | A squashed instruction in LSU stage 1 is gone by the clock edge that ends the squash cycle | LSU | The SQ drops a fill only in the squash cycle. Its slot can be reallocated from the next cycle, so a later fill would corrupt another store's entry |
| D2 | In-flight LSU entries younger than a squash produce no result, and their memory responses are still consumed in order | LSU | Memory requests cannot be cancelled; removing entries would misalign the in-flight FIFO with later responses. One possible approach: a per-entry killed bit in the in-flight FIFO (`Fifo.v` does not support per-entry updates) |
| D3 | The ROB never commits a squashed instruction, including one whose writeback arrives after the squash | ROB | Commit pops the SQ on a `seq_num` match with the ROB head (I4) |
| D4 | A squashed instruction's late writeback is never taken as the new instruction that reuses its `seq_num` | ROB | `SeqNumGenL3` rewinds on a squash. The SQ is safe on its own (entries are removed in the squash cycle), the ROB is not |
| D5 | The commit unit's writeback register (`X_reg`) drops squashed instructions | ROB | Same as D3 |
| D6 | Execute pipes and `ExQueue`s drop squashed instructions | Execute units | No side effects from younger instructions; the SQ relies on this only through D1 |
| D7 | Rename recovery copies committed mappings back on an exception | Rename | No interaction: SQ and CSB entries hold values, not register mappings. Listed for completeness |
| D8 | The `CSRFile` trap squash is an input of `SquashUnitL1`, and the commit unit subscribes to the arbitrated squash | Top | The SQ must see every squash, including traps taken at commit |

## 9. Limitations and future work

- **MMIO side effects.** Once loads can be squashed after issue, a squashed load from a side-effecting address (for example STDIN at
  `0xF0000004`) has already popped the device. A possible fix is a non-speculative load buffer: an MMIO load is parked there without
  accessing memory, the LSU keeps processing younger instructions, and the parked load is sent once its `seq_num` is the oldest in flight
  (`SeqAge`). Parked MMIO loads would stay in order among themselves. Two related effects: MMIO stores (STDOUT, the exit store at
  `0xFFFFFFFC`) now take effect at retire, after commit, so output can lag a later STDIN read; and forwarding treats device addresses
  like memory, so a load from an address with a buffered store returns the stored value instead of reading the device.
- **Exception producers** in the LSU (misaligned and faulting accesses) are not added. They must preserve I3.
- **Retire throughput** is one write per memory round trip. A `send` pointer between `head` and `tail` would allow one write per cycle.
- **Misaligned accesses** that cross a word boundary stay silently truncated, as today. Forwarding truncates them the same way memory
  does, so it adds no new mismatch.
- **FENCE** remains a no-op and does not wait for the CSB to drain. Instruction fetch does not search the SQ or CSB, so code written by
  stores is visible to fetch only after retire.

## 10. Costs

- **State:** SQ entry about 73 bits (`val`, `filled`, `seq_num`, `addr`, `strb`, `data`), 4 entries; CSB entry about 67 bits, 4 entries;
  37 more bits per LSU in-flight FIFO entry.
- **Search:** per structure, one 30-bit address comparator per entry, 4 circular priority encoders (one per lane) and 4 byte
  multiplexers.
- **Long combinational paths:**
  - LSU stage 1: address add, address compare, youngest select, SQ/CSB merge, full-cover check, then `mem.req_val` and `D.rdy`.
  - Retire to fetch: `store_mem.resp_val` to `pop`, `push_rdy`, `commit_ok`, then both `commit.val` (through `CSRNotif`, `CSRFile` and
    `SquashUnitL1` to fetch, decode and the SQ) and `sq_deq_en` (through `alloc_rdy` and the decode stall to `F.rdy`).

## 11. Implementation

**Order:**

1. `CircularPriorityEncoder`, `StoreBufferSearch`.
2. `StoreQueueIntf`, `CompletedStoreBufferIntf`; `D__XIntf.sq_idx`.
3. `StoreQueue`, `CompletedStoreBuffer`.
4. `WritebackCommitUnitL5`.
5. `InstDecoder` `store` column; `DecodeIssueUnitL7`.
6. `LoadStoreUnitL9`.

Every new module and changed unit gets a line trace in the style of [ROB.v](hw/writeback_commit/ROB.v).

**Requirements on the top level and memory system** (not built here; the correctness argument in section 6 relies on them):

| # | Requirement | Relied on by |
|---|---|---|
| T1 | Exactly one `LoadStoreUnitL9` handles every load and store (one pipe subset contains all load and store uops) | I2 |
| T2 | A write is acknowledged only once any later read, from any memory client, observes it | I8. Met today: every address maps to one server, and each server performs a write before sending its ack ([MemIntfTestServer_2Port.v](test/fl/MemIntfTestServer_2Port.v), [FPGAMem.v](fpga/FPGAMem.v), and the sp26 SRAM wrapper `top/sp26/rtl/tapein2/wrapper_memory.sv`, which writes in M0 before queueing the response). The sp26 crossbar's response ROB can only delay an ack, so it preserves this but does not provide it. Memory that acknowledges a write before performing it (for example a posted-write buffer) would break it |
| T3 | Each client receives the responses to its own requests, in request order | `LoadStoreUnitL9`'s in-flight FIFO. Provided by the sp26 crossbar (`top/sp26/rtl/tapein2/mem_xbar.sv`): each client's request router tags requests with a per-client sequence number in `opaque`, and a per-client ROB (`ip/reorder_buffer/rtl/rob_arbiter.sv`) returns responses in that order, even across servers |
| T4 | Loads have priority over retire writes, and retire writes are served whenever the LSU is not requesting | I11 (liveness); priority is a performance choice. In the sp26 crossbar's fixed-priority request arbiters, the retire client goes below `dmem` |
| T5 | Both new interfaces are instantiated, the arbitrated `SquashNotif` reaches the commit unit (D8), and `store_mem` is a second data-memory client | Integration. In the sp26 crossbar this is a fifth client port with its own request router and response ROB. The router overwrites `opaque`, so the value the CSB drives there does not matter |

**Known impacts:**

- Older decode units leave the new `InstDecoder` output unconnected: one more `PINMISSING` lint warning each, as with `serialize`.
- `D__XIntf.sq_idx` is undriven in older tops; the lint waivers in section 4.3 cover it.
- `commit.val` can now be low while the ROB head is valid. Its subscribers (rename free list, `SeqAge`, `SeqNumGenL3`, decode's
  serialization barriers, `CSRNotif`) only act on `commit.val`, so a stall only delays them.
