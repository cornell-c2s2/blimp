# ROB formal verification

See [RESULTS.md](RESULTS.md) for the verified parameter and mutation regression.

This JasperGold suite checks `hw/writeback_commit/ROB.v` with eleven safety
assertions: five local control checks, four properties against an independent
scoreboard, and two storage refinement checks. The default is the BlimpV7/V8
integration configuration: **32 entries, 76-bit payloads**. Five sequence bits
select 32 entries, and the L3 WCU payload is
`pc[31:0]`, `waddr[4:0]`, `wdata[31:0]`, `wen`, and `ppreg[5:0]` (36 physical
registers require six address bits).

## Properties

`rob_assertions.sv` binds the original checks into the DUT: head bypass, valid
head visibility, empty-head blocking, pointer advancement, and pointer stability.

`rob_scoreboard.sv` observes only ROB ports. It tracks pending completions for all
slots and the input payload for an arbitrary fixed slot selected by `watch_idx`.
That selector can be any valid index, so the payload proof must hold for every
possible slot, rather than a hand-picked index. Keeping one reference payload
avoids duplicating the whole DUT's data state. The model advances its own integer
head on its independently calculated dequeue condition; it never reads DUT
storage, pointer state, or readiness to update its state. It proves:

- `ap_ready_matches_model`: readiness is exactly a pending head or an arriving
  completion for that head, even when `deq_en=0`.
- `ap_index_matches_model`: the output index is the model's oldest position.
- `ap_payload_matches_model`: every expected dequeue of the arbitrary watched
  slot returns its recorded input payload, or its arriving payload during bypass.
- `ap_no_phantom_dequeue`: a DUT dequeue has a matching pending/arriving
  completion. Consumed entries cannot silently reappear on wraparound.

Two additional assertions in the harness compare the watched DUT entry's valid
bit and payload with the independent reference state. These prove preservation
even while an older instruction blocks dequeue and serve as inductive lemmas
for the output proof. DUT state is only observed by these assertions and never
drives the reference model. Jasper may reuse already proven assertions as lemmas;
the script still requires every assertion, including the lemmas, to be proven.

With the legal producer contract, these are safety checks for message
preservation, in-order consumption, and absence of duplicate consumption between
slot uses. They do **not** prove eventual retirement: missing older completions
or a consumer that never dequeues can stall forever. There are no fairness
assumptions. This is a ROB unit proof, not an instruction-allocation or WCU
integration proof; a stale completion for an already reused index cannot be
identified by the ROB interface alone.

Eight explicit scenario covers exercise bypass, out-of-order arrivals, wraparound,
arrival with dequeue disabled, a stored-head stall, concurrent insertion and
retirement of different slots, filling/draining every entry, and two full wraps
followed by an empty ROB. Jasper also creates antecedent reachability covers.

## Assumptions and elaboration

- An enabled insertion has an index less than `p_depth`. This excludes unused
  binary encodings for non-power-of-two depths; at power-of-two depths it imposes
  no restriction.
- By default, an enabled insertion cannot overwrite a pending completion in the
  **reference** scoreboard. Index reuse after consumption remains allowed.
  `ROB_LEGAL_TRAFFIC=0` removes this assumption and instead checks the existing
  RTL's last-writer-wins behavior for duplicate completions.
- Arrival order, payload values, and dequeue enable are otherwise unconstrained.
  No property about DUT outputs is assumed.
- The verification-only selector `watch_idx` is in range and stable throughout
  the active run. It is independent of completion traffic and not a DUT input.
- `reset rst` initializes the synchronous-reset state before proof; the suite
  does not independently exercise reset reassertion in an active run.
- `FORMAL` selects the existing Jasper-compatible RTL reset. `SYNTHESIS` removes
  simulation-only tracing. Automatic blackboxing is disabled, and unexpected
  blackboxes, stopats, or undriven internal signals cause failure. The complete
  DUT storage participates in the proof, including the 32x76 configuration.

Each configuration is a separate finite hardware instance. `proven` means an
unbounded safety proof for that instance, not a proof for every parameter value.
The script rejects bounded-only and unresolved results. Depth 1 is not claimed:
the RTL's `$clog2(p_depth)` index declaration does not special-case it.

## Run

From this directory:

```sh
source /classes/c2s2/setup-c2s2.sh
module load cadence
jaspergold -batch -tcl run.tcl
```

Optional environment variables are `ROB_DEPTH` (at least 2), `ROB_MSG_BITS`,
`ROB_LEGAL_TRAFFIC` (0 or 1), `ROB_REPORT` (text report destination),
`ROB_JSON` (Jasper FPV JSON export), and `ROB_RTL`
(alternate RTL file for isolated mutations). For example:

```sh
ROB_DEPTH=3 ROB_MSG_BITS=8 ROB_REPORT=/tmp/rob_depth3.txt \
  jaspergold -batch -proj /tmp/rob_depth3_jg -tcl run.tcl
```

`run.tcl` returns a nonzero exit status unless all eleven assertions are `proven`
and all covers are `covered`. A successful tool launch alone is not a pass.

## Parameter and mutation regression

```sh
python3 check.py
```

This runs depths 2, 3, 4, and 5 with 8-bit payloads, 4x76 and 32x76 with legal
traffic, and 4x8 without the no-overwrite assumption. It then tests four isolated
mutations of a temporary copy of the RTL:

| Injected fault | Required counterexample |
| --- | --- |
| Flip a bit when storing a payload | `ap_payload_matches_model` |
| Drop all stored insertions | `ap_ready_matches_model` |
| Stop clearing consumed entries | `ap_ready_matches_model` |
| Require dequeue enable to assert arrival readiness | `ap_ready_matches_model` |

A mutation counts as detected only if the named scoreboard assertion has an
actual `cex`; parser errors, timeouts, or unreachable covers are not enough.
Generated RTL, projects, console logs, reports, and `results.json` go to a fresh
temporary directory printed at startup. No repository RTL is modified.
Use `--proofs-only`, `--mutations-only`, or `--output PATH` as needed. Each
Jasper proof has a 120-second limit; each tool invocation has a 300-second limit.
