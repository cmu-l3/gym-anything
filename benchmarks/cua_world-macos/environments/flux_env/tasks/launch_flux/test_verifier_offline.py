"""Offline mock tests for verify_flux_running.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/flux_env/tasks/launch_flux/test_verifier_offline.py

The smoke verifier only calls `env_info["exec_capture"](cmd)` with two
canned commands. We mock that callable to drive every branch of the
scoring path:

  Scenario               | pgrep -x  | lsappinfo grep   | expected score / passed
  ---------------------- | --------- | ---------------- | ---------------------
  Flux fully running     | "3617"    | bundle path line | 100 / True
  Flux not running       | ""        | ""               |   0 / False
  Process up, no ls reg. | "3617"    | ""               |  50 / False   (transient — partial)
  Stale ls entry only    | ""        | bundle path line |   0 / False   (passed requires both)

The smoke task's premise is "pre_task launches Flux"; under do-nothing
(i.e. the env starts but no agent action), the env STILL auto-launches
Flux, so happy-path == do-nothing. The "Flux not running" scenario only
arises if pre_task itself failed (install missing, sandbox lost, etc.) —
the verifier must correctly score that 0.

Exits non-zero on any assertion failure so CI can gate on it.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
VERIFIER_PATH = HERE / "verifier.py"
spec = importlib.util.spec_from_file_location("verifier", VERIFIER_PATH)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
verify = mod.verify_flux_running


def make_env_info(pgrep_stdout: str, lsapp_stdout: str) -> dict:
    """Return an env_info whose `exec_capture` returns canned stdout for the
    two specific commands the verifier issues."""
    def exec_capture(cmd: str) -> str:
        if "pgrep" in cmd:
            return pgrep_stdout
        if "lsappinfo" in cmd:
            return lsapp_stdout
        raise AssertionError(f"unexpected exec_capture cmd: {cmd!r}")
    return {"exec_capture": exec_capture}


LSAPP_REAL_ENTRY = (
    '31) "Flux" ASN:0x0-0x36036:\n'
    '    bundleID="org.herf.Flux"\n'
    '    bundle path="/Applications/Flux.app"\n'
    '    executable path="/Applications/Flux.app/Contents/MacOS/Flux"\n'
)


def run(name: str, pgrep_out: str, lsapp_out: str, expect_score: int, expect_passed: bool) -> bool:
    out = verify(traj={}, env_info=make_env_info(pgrep_out, lsapp_out), task_info={})
    score = out["score"]; passed = out["passed"]
    ok = (score == expect_score) and (passed == expect_passed)
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {name}: got score={score} passed={passed} "
          f"(expected score={expect_score} passed={expect_passed})")
    if not ok:
        print(f"    feedback: {out['feedback']}")
    return ok


if __name__ == "__main__":
    print("=== Offline verifier tests: launch_flux ===")
    results = [
        # Happy path: process running + lsappinfo registered.
        run("flux_fully_running",     "3617",  LSAPP_REAL_ENTRY, expect_score=100, expect_passed=True),
        # Catastrophic failure: pre_task didn't launch Flux at all.
        run("flux_not_running",       "",      "",                expect_score=0,   expect_passed=False),
        # Transient: process started but lsappinfo hasn't registered yet
        # (e.g. caught mid-launch). Verifier awards 50 (partial), still fails.
        run("process_only_no_lsreg",  "3617",  "",                expect_score=50,  expect_passed=False),
        # Defensive: stale lsappinfo entry but process gone. Should NOT pass.
        run("lsreg_only_no_process",  "",      LSAPP_REAL_ENTRY, expect_score=0,   expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
