"""Offline mock tests for verify_ntfs_automount_agent.

Per task_creation_notes/13_file_content_verification_and_offline_testing.md.

Gate 1: no work at all → score 0.
Gate 2: brew_present=False AND ntfs3g_present=False → cap total at 50.

Scoring recap (100 pts, pass at 70):
  C1  10 pts  Homebrew binary present
  C2  15 pts  ntfs-3g binary present
  C3  20 pts  ntfs-automount.sh (exists+exec+diskutil); partial 5 pts if exists only
  C4  15 pts  NTFS detection substring in automount.sh
  C5  15 pts  mount command substring (ntfs-3g or mount_ntfs)
  C6   5 pts  ntfs-unmount.sh exists+exec
  C7  20 pts  LaunchAgent plist (Label + WatchPaths=[/Volumes])

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/macfuse_env/tasks/ntfs_automount_agent/test_verifier_offline.py
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
verify = mod.verify_ntfs_automount_agent

TASK_INFO = {"metadata": {"pass_threshold": 70}}


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


def _no_files() -> dict:
    return {
        "brew_present": False, "brew_path": None,
        "ntfs3g_present": False, "ntfs3g_path": None,
        "automount_sh_exists": False, "automount_sh_executable": False,
        "automount_sh_has_diskutil": False, "automount_sh_has_ntfs_check": False,
        "automount_sh_has_mount_cmd": False,
        "unmount_sh_exists": False, "unmount_sh_executable": False,
        "plist_exists": False, "plist_valid": False,
        "plist_label_correct": False, "plist_watchpaths_has_volumes": False,
    }


def _full_correct() -> dict:
    return {
        "brew_present": True, "brew_path": "/opt/homebrew/bin/brew",
        "ntfs3g_present": True, "ntfs3g_path": "/opt/homebrew/bin/ntfs-3g",
        "automount_sh_exists": True, "automount_sh_executable": True,
        "automount_sh_has_diskutil": True, "automount_sh_has_ntfs_check": True,
        "automount_sh_has_mount_cmd": True,
        "unmount_sh_exists": True, "unmount_sh_executable": True,
        "plist_exists": True, "plist_valid": True,
        "plist_label_correct": True, "plist_watchpaths_has_volumes": True,
    }


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

DO_NOTHING = None  # result file missing → score 0, passed=False

# Gate 1: all False → score 0
ALL_FALSE = _no_files()

# Files-only without tools (Gate 2 fires):
# C3+C4+C5+C6+C7 = 20+15+15+5+20 = 75, capped to 50 by Gate 2 → fail
FILES_NO_TOOLS = {**_no_files(),
                  "automount_sh_exists": True, "automount_sh_executable": True,
                  "automount_sh_has_diskutil": True, "automount_sh_has_ntfs_check": True,
                  "automount_sh_has_mount_cmd": True,
                  "unmount_sh_exists": True, "unmount_sh_executable": True,
                  "plist_exists": True, "plist_valid": True,
                  "plist_label_correct": True, "plist_watchpaths_has_volumes": True}

# Brew + ntfs3g only (no scripts/plist): C1+C2 = 25 (fail)
TOOLS_ONLY = {**_no_files(), "brew_present": True, "brew_path": "/opt/homebrew/bin/brew",
              "ntfs3g_present": True, "ntfs3g_path": "/opt/homebrew/bin/ntfs-3g"}

# C3 partial only (script exists, not exec): C1+C2+C3_partial+no-rest = 10+15+5 = 30 (fail)
PARTIAL_AUTOMOUNT = {**_full_correct(),
                     "automount_sh_executable": False, "automount_sh_has_diskutil": False,
                     "automount_sh_has_ntfs_check": False, "automount_sh_has_mount_cmd": False,
                     "unmount_sh_exists": False, "unmount_sh_executable": False,
                     "plist_exists": False, "plist_valid": False,
                     "plist_label_correct": False, "plist_watchpaths_has_volumes": False}
# Score: 10+15+5(partial C3)+0+0+0+0 = 30

# Full correct: 100 (pass)
FULL = _full_correct()

# Without plist: C1+C2+C3+C4+C5+C6 = 10+15+20+15+15+5 = 80 (pass)
NO_PLIST = {**_full_correct(),
            "plist_exists": False, "plist_valid": False,
            "plist_label_correct": False, "plist_watchpaths_has_volumes": False}


if __name__ == "__main__":
    print("=== Offline verifier tests: ntfs_automount_agent ===")
    results = [
        run("do-nothing (result file missing)",            DO_NOTHING,        expect_score=0,   expect_passed=False),
        run("do-nothing (all false, Gate 1)",              ALL_FALSE,         expect_score=0,   expect_passed=False),
        run("files-only, no tools (Gate 2 cap=50)",        FILES_NO_TOOLS,    expect_score=50,  expect_passed=False),
        run("tools-only, no scripts (25/100)",             TOOLS_ONLY,        expect_score=25,  expect_passed=False),
        run("partial automount — not exec (30/100)",       PARTIAL_AUTOMOUNT, expect_score=30,  expect_passed=False),
        run("no plist (80/100)",                           NO_PLIST,          expect_score=80,  expect_passed=True),
        run("full correct (100/100)",                      FULL,              expect_score=100, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
