# ROB formal regression — 2026-10-18

Tool: JasperGold 2024.09 FCS, with the C2S2 setup and `module load cadence`.
Reproduce from `formal/rob` with `python3 check.py`.

## Unmodified RTL

| Entries | Payload bits | Producer mode | Assertions | Covers |
| --- | --- | --- | --- | --- |
| 2 | 8 | No pending-slot overwrite | 11 proven | All reached |
| 3 | 8 | No pending-slot overwrite | 11 proven | All reached |
| 4 | 8 | No pending-slot overwrite | 11 proven | All reached |
| 5 | 8 | No pending-slot overwrite | 11 proven | All reached |
| 4 | 76 | No pending-slot overwrite | 11 proven | All reached |
| 32 | 76 | No pending-slot overwrite (V7/V8 defaults) | 11 proven | All reached |
| 4 | 8 | Overwrites allowed; last writer wins | 11 proven | All reached |

All assertions report `proven` with bound `Infinite`; none are merely bounded
passes. Each configuration's batch process exits 0. The 32x76 run reaches all
19 covers (8 explicit scenarios plus tool-generated antecedent covers).
No automatic blackboxing, stopats, or undriven internal signals are permitted.

The pending-bit and payload storage refinement assertions are independently
proven and help the output payload proof converge. The reference model tracks
every pending slot and the payload of a universally selected, stable slot;
the DUT storage remains fully modeled.

## Isolated fault injections

Each fault was applied to a temporary copy of the RTL at 4 entries / 8 bits.
The regression requires a real counterexample for the named scoreboard property;
a tool error or unreachable cover is not accepted as fault detection.

| Fault | Property with counterexample | Outcome |
| --- | --- | --- |
| Corrupt a stored payload bit | `ap_payload_matches_model` | Detected |
| Drop stored insertions | `ap_ready_matches_model` | Detected |
| Do not clear a consumed entry | `ap_ready_matches_model` | Detected |
| Gate arriving-head readiness with dequeue enable | `ap_ready_matches_model` | Detected |

Each mutant's batch process exits 1 as expected; the overall regression exits 0.
The original five assertions still pass the readiness mutation, demonstrating
why the independent readiness check is necessary.

## Scope

These are safety proofs for the tested hardware instances under the documented
index-range, reset, and producer contracts. They do not prove eventual retirement,
mid-run reset handling, or the upstream allocation/WCU protocol. See `README.md`
for the complete assumptions and instructions.
