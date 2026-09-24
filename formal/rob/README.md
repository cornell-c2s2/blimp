# ROB formal verification

This JasperGold proof targets `hw/writeback_commit/ROB.v` with a 4-entry,
8-bit-message instance. Completion insertions are deliberately unconstrained:
they can arrive in any index order, matching independent execute units.

The assertions prove that:

- a same-cycle completion of the commit head bypasses with the exact message;
- a valid head is the only non-bypass dequeue result;
- an empty head is not ready without a completion for that head; and
- a dequeue advances the head by exactly one slot, including wraparound, while
  no dequeue leaves it unchanged.

Run the proof from this directory:

```sh
source /classes/c2s2/setup-c2s2.sh
module load cadence
jaspergold -batch -tcl run.tcl
```

The three cover properties exercise bypass, inverted completion order, and
pointer wraparound. The proof does not assume that producer indices arrive in
order; environmental rules such as "an XU completes a given instruction once"
belong in a higher-level WCU integration proof.
