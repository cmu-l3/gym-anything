"""Offline mock tests for verify_macfuse_python_passthrough.

Per task_creation_notes/13_file_content_verification_and_offline_testing.md.

Gate 1: no script AND no source_dir → score 0.
Gate 2 (wrong-target): script exists but no fuse mention → C3–C7 forced 0.

Scoring recap (100 pts, pass at 70):
  C1  15 pts  mfusepy importable
  C2  10 pts  script exists, fresh, >= 500 bytes
  C3  10 pts  `from fuse import ...` line
  C4  10 pts  class subclassing Operations
  C5  20 pts  >= 5 FUSE op methods defined
  C6  10 pts  script references `fuse-access.log`
  C7  10 pts  FUSE() call with nothreads=True or foreground=True
  C8  10 pts  python3 -m py_compile passes
  C9   5 pts  ~/Documents/source/ with >= 1 file

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/macfuse_env/tasks/macfuse_python_passthrough/test_verifier_offline.py
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verifier", HERE / "verifier.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
verify = mod.verify_macfuse_python_passthrough

TASK_INFO = {"metadata": {"pass_threshold": 70, "min_script_bytes": 500, "required_method_min_count": 5}}


def make_env_info(result: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(result).encode())
    fixture.close()

    def copy_from_env(_r, local):
        shutil.copy(fixture.name, local)

    return {"copy_from_env": copy_from_env, "_fixture": fixture.name}


def make_env_missing() -> dict:
    def copy_from_env(_r, _l):
        raise FileNotFoundError("no result")

    return {"copy_from_env": copy_from_env}


def run(name: str, result, expect_score, expect_passed: bool) -> bool:
    if result is None:
        env_info = make_env_missing()
    else:
        env_info = make_env_info(result)
    out = verify(traj={}, env_info=env_info, task_info=TASK_INFO)
    if "_fixture" in env_info:
        Path(env_info["_fixture"]).unlink(missing_ok=True)
    score = out["score"]
    passed = out["passed"]
    if isinstance(expect_score, tuple):
        lo, hi = expect_score
        score_ok = lo <= score <= hi
        expect_desc = f"{lo}..{hi}"
    else:
        score_ok = score == expect_score
        expect_desc = str(expect_score)
    pass_ok = passed == expect_passed
    ok = score_ok and pass_ok
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: score={score} passed={passed} "
          f"(expected score={expect_desc} passed={expect_passed})")
    if not ok:
        print(f"    subscores: {out['subscores']}")
        print(f"    feedback:  {out['feedback'][:300]}")
    return ok


def _no_work() -> dict:
    return {
        "mfusepy_importable": False,
        "script_exists": False, "script_fresh": False, "script_size": 0,
        "syntax_ok": False,
        "source_dir_exists": False, "source_file_count": 0,
        "has_fuse_import": False, "subclasses_operations": False,
        "method_count": 0, "method_names": [],
        "logs_to_access_log": False, "fuse_call_with_flags": False,
        "mentions_fuse": False,
    }


def _full_correct() -> dict:
    return {
        "mfusepy_importable": True,
        "script_exists": True, "script_fresh": True, "script_size": 1200,
        "syntax_ok": True,
        "source_dir_exists": True, "source_file_count": 3,
        "has_fuse_import": True, "subclasses_operations": True,
        "method_count": 6,
        "method_names": ["getattr", "readdir", "open", "read", "write", "create"],
        "logs_to_access_log": True, "fuse_call_with_flags": True,
        "mentions_fuse": True,
    }


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

DO_NOTHING = None  # file missing → 0

# Gate 1: no script, no source dir → 0
NO_WORK = _no_work()

# Wrong-target (Gate 2): script exists but no fuse mention
# C1=0, C2=10 (exists+fresh+big), C3-C7=0 (gate), C8=10, C9=5 → 25 (fail)
WRONG_TARGET = {**_no_work(),
                "script_exists": True, "script_fresh": True, "script_size": 700,
                "syntax_ok": True, "mentions_fuse": False,
                "source_dir_exists": True, "source_file_count": 2}

# mfusepy installed + script but only 3 methods (< 5) → C5=0
# C1=15, C2=10, C3=10, C4=10, C5=0, C6=10, C7=10, C8=10, C9=5 → 80? wait C5=0 → 65 (fail)
PARTIAL_METHODS = {**_full_correct(), "method_count": 3,
                   "method_names": ["getattr", "readdir", "open"]}
# Score: 15+10+10+10+0+10+10+10+5 = 80. Hmm — 80 > 70, so it passes.
# Let me remove C6 too (no log path) → 15+10+10+10+0+0+10+10+5 = 70 → at threshold (passes).
# Remove C7 too → 15+10+10+10+0+0+0+10+5 = 60 (fail). That's a cleaner partial.

PARTIAL = {**_full_correct(),
           "method_count": 3, "method_names": ["getattr", "readdir", "open"],
           "logs_to_access_log": False, "fuse_call_with_flags": False}
# Score: 15+10+10+10+0+0+0+10+5 = 60 (fail)

# No mfusepy: C1=0, rest full → 85 (pass)
NO_MFUSEPY = {**_full_correct(), "mfusepy_importable": False}
# Score: 0+10+10+10+20+10+10+10+5 = 85 (pass)

# Full correct: 100 (pass)
FULL = _full_correct()


if __name__ == "__main__":
    print("=== Offline verifier tests: macfuse_python_passthrough ===")
    results = [
        run("do-nothing (result file missing)",          DO_NOTHING,      expect_score=0,   expect_passed=False),
        run("do-nothing (no script, no source dir)",     NO_WORK,         expect_score=0,   expect_passed=False),
        run("wrong-target (no fuse mention, Gate 2=25)", WRONG_TARGET,    expect_score=25,  expect_passed=False),
        run("partial (3 methods, no log, no FUSE call=60)", PARTIAL,      expect_score=60,  expect_passed=False),
        run("no mfusepy installed (85/100)",             NO_MFUSEPY,      expect_score=85,  expect_passed=True),
        run("full correct (100/100)",                    FULL,            expect_score=100, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
