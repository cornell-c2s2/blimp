#!/usr/bin/env python3
"""Run ROB proof configurations and isolated fault-injection regressions.

Source the course setup and load cadence first. Generated RTL, Jasper projects,
logs, and reports stay in a fresh temporary directory (or --output directory).
The repository RTL is never modified by mutation testing.
"""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile


HERE = Path(__file__).resolve().parent
RTL = HERE.parents[1] / "hw/writeback_commit/ROB.v"
CONFIGS = [
    ("depth2", 2, 8, 1),
    ("depth3", 3, 8, 1),
    ("depth4", 4, 8, 1),
    ("depth5", 5, 8, 1),
    ("small_wcu_payload", 4, 76, 1),
    ("blimp_v8_default", 32, 76, 1),
    ("unrestricted", 4, 8, 0),
]
# Each mutation must fail a specific *independent scoreboard* property.
# A parser error or merely an unreachable cover does not count as detection.
MUTATIONS = {
    "corrupt_stored_payload": (
        "msg: ins_msg,", "msg: ins_msg ^ p_msg_bits'(1),",
        "ap_payload_matches_model",
    ),
    "drop_insertions": (
        "if( ins_en & !bypass ) begin", "if( 1'b0 ) begin",
        "ap_ready_matches_model",
    ),
    "keep_consumed_entry": (
        "entries[deq_ptr] <= '{msg: 'x, val: 1'b0};",
        "entries[deq_ptr] <= entries[deq_ptr];",
        "ap_ready_matches_model",
    ),
    "ready_depends_on_enable": (
        "( can_bypass & ins_en );", "( can_bypass & ins_en & deq_en );",
        "ap_ready_matches_model",
    ),
}


def run_case(output, name, depth, bits, legal, rtl, expected_cex=None):
    case = output / name
    case.mkdir()
    env = os.environ.copy()
    env.update(ROB_DEPTH=str(depth), ROB_MSG_BITS=str(bits),
               ROB_LEGAL_TRAFFIC=str(legal), ROB_RTL=str(rtl),
               ROB_REPORT=str(case / "report.txt"))
    with (case / "console.log").open("w") as log:
        try:
            process = subprocess.Popen(
                ["jaspergold", "-batch", "-proj", str(case / "jgproject"),
                 "-tcl", "run.tcl"], cwd=HERE, env=env,
                stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
            )
            process.wait(timeout=300)
        except subprocess.TimeoutExpired:
            # Terminate only this test's process group, including proof engines.
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            print(f"FAIL {name}: process timed out", flush=True)
            return dict(name=name, passed=False, reason="timeout")
    report_file = case / "report.txt"
    report = report_file.read_text() if report_file.exists() else ""
    if expected_cex:
        # Detailed reports list property, status, engine, bound, and time.
        detected = any(expected_cex in line and re.search(r"\bcex\b", line)
                       for line in report.splitlines())
        passed = process.returncode != 0 and detected
        label = f"detected by {expected_cex}" if passed else "expected counterexample missing"
    else:
        passed = process.returncode == 0 and bool(report)
        label = "all assertions proven; all covers reached" if passed else "proof failed (see console.log)"
    print(f"{'PASS' if passed else 'FAIL'} {name}: {label}", flush=True)
    return dict(name=name, depth=depth, msg_bits=bits, legal_traffic=legal,
                passed=passed, returncode=process.returncode,
                expected_counterexample=expected_cex, report=str(report_file))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mutations-only", action="store_true")
    parser.add_argument("--proofs-only", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.mutations_only and args.proofs_only:
        parser.error("choose at most one of --mutations-only and --proofs-only")
    output = (args.output or Path(tempfile.mkdtemp(prefix="rob-formal-"))).resolve()
    output.mkdir(parents=True, exist_ok=True)
    print(f"Artifacts: {output}", flush=True)
    results = []
    if not args.mutations_only:
        for name, depth, bits, legal in CONFIGS:
            results.append(run_case(output, name, depth, bits, legal, RTL))
    if not args.proofs_only:
        original = RTL.read_text()
        for name, (old, new, prop) in MUTATIONS.items():
            if original.count(old) != 1:
                raise RuntimeError(f"Mutation {name} no longer matches exactly one RTL location")
            mutant = output / f"{name}.v"
            mutant.write_text(original.replace(old, new))
            results.append(run_case(output, name, 4, 8, 1, mutant, prop))
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
