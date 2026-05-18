"""Offline mock tests for verify_macfuse_sysinfo_fuse_c.

Per task_creation_notes/13_file_content_verification_and_offline_testing.md
(Gap 2). Gate 1 fires when project_dir_exists=False → score 0 immediately.

Scoring recap (100 pts, pass at 70):
  C1 project_dir        5
  C2 source >200 bytes 10
  C3 FUSE_USE_VERSION  15  (define BEFORE include)
  C4 fuse.h include    10
  C5 4 callbacks       20  (5 each: getattr/readdir/open/read)
  C6 >=2 sysctl calls  15
  C7 4 filenames       10  (2.5 each → table: 4=10,3=7,2=5,1=2,0=0)
  C8 Makefile          10  (5 FUSE_USE_VERSION=26 + 5 pkg-config)
  C9 Mach-O binary      5  (bonus)

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/macfuse_env/tasks/macfuse_sysinfo_fuse_c/test_verifier_offline.py
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
verify = mod.verify_macfuse_sysinfo_fuse_c

TASK_INFO = {"metadata": {"pass_threshold": 70, "min_source_bytes": 200, "min_sysctl_calls": 2}}


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


def _no_source_analysis():
    return {
        "has_fuse_use_version_define": False,
        "fuse_use_version_before_include": False,
        "fuse_use_version_value": None,
        "has_fuse_h_include": False,
        "callbacks_defined": {"getattr": False, "readdir": False, "open": False, "read": False},
        "sysctl_call_count": 0,
        "filenames_present": {"cpu.txt": False, "memory.txt": False,
                              "uptime.txt": False, "hostname.txt": False},
    }


def _full_source_analysis():
    return {
        "has_fuse_use_version_define": True,
        "fuse_use_version_before_include": True,
        "fuse_use_version_value": 26,
        "has_fuse_h_include": True,
        "callbacks_defined": {"getattr": True, "readdir": True, "open": True, "read": True},
        "sysctl_call_count": 4,
        "filenames_present": {"cpu.txt": True, "memory.txt": True,
                              "uptime.txt": True, "hostname.txt": True},
    }


def _full_makefile_analysis():
    return {"has_fuse_use_version_26": True, "has_pkg_config_fuse": True}


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

# Gate 1: no project dir → score 0 immediately
DO_NOTHING = None

NO_PROJECT_DIR = {
    "project_dir_exists": False,
    "source_exists": False, "source_bytes": 0,
    "makefile_exists": False,
    "binary_exists": False, "binary_is_macho": False,
    "source_analysis": _no_source_analysis(),
    "makefile_analysis": {},
}

# Project dir exists, small stub file, no content of interest
# C1=5, C2=0 (too small), rest 0 → 5 (fail)
STUB_ONLY = {
    "project_dir_exists": True,
    "source_exists": True, "source_bytes": 50,
    "makefile_exists": False,
    "binary_exists": False, "binary_is_macho": False,
    "source_analysis": _no_source_analysis(),
    "makefile_analysis": {},
}

# Good file size + fuse.h include + 3 callbacks + 1 filename
# but no FUSE_USE_VERSION define, no sysctl, no Makefile, no binary
# C1=5, C2=10, C3=0, C4=10, C5=15, C6=0, C7=2, C8=0, C9=0 → 42 (fail)
PARTIAL = {
    "project_dir_exists": True,
    "source_exists": True, "source_bytes": 800,
    "makefile_exists": False,
    "binary_exists": False, "binary_is_macho": False,
    "source_analysis": {
        "has_fuse_use_version_define": False,
        "fuse_use_version_before_include": False,
        "fuse_use_version_value": None,
        "has_fuse_h_include": True,
        "callbacks_defined": {"getattr": True, "readdir": True, "open": True, "read": False},
        "sysctl_call_count": 0,
        "filenames_present": {"cpu.txt": True, "memory.txt": False,
                              "uptime.txt": False, "hostname.txt": False},
    },
    "makefile_analysis": {},
}

# define AFTER include (incorrect ordering): C3=0 even though define exists
# C1=5, C2=10, C3=0, C4=10, C5=20, C6=15, C7=10, C8=10, C9=0 → 80 (pass)
DEFINE_AFTER_INCLUDE = {
    "project_dir_exists": True,
    "source_exists": True, "source_bytes": 1200,
    "makefile_exists": True,
    "binary_exists": False, "binary_is_macho": False,
    "source_analysis": {
        "has_fuse_use_version_define": True,
        "fuse_use_version_before_include": False,  # define is AFTER include
        "fuse_use_version_value": 26,
        "has_fuse_h_include": True,
        "callbacks_defined": {"getattr": True, "readdir": True, "open": True, "read": True},
        "sysctl_call_count": 3,
        "filenames_present": {"cpu.txt": True, "memory.txt": True,
                              "uptime.txt": True, "hostname.txt": True},
    },
    "makefile_analysis": _full_makefile_analysis(),
}

# Full correct, no binary: C1+C2+C3+C4+C5+C6+C7+C8+C9 = 5+10+15+10+20+15+10+10+0 = 95 (pass)
FULL_NO_BINARY = {
    "project_dir_exists": True,
    "source_exists": True, "source_bytes": 1500,
    "makefile_exists": True,
    "binary_exists": False, "binary_is_macho": False,
    "source_analysis": _full_source_analysis(),
    "makefile_analysis": _full_makefile_analysis(),
}

# Full correct with binary: 100 (pass)
FULL_WITH_BINARY = {**FULL_NO_BINARY, "binary_exists": True, "binary_is_macho": True}


if __name__ == "__main__":
    print("=== Offline verifier tests: macfuse_sysinfo_fuse_c ===")
    results = [
        run("do-nothing (result file missing)",        DO_NOTHING,           expect_score=0,  expect_passed=False),
        run("no project dir (Gate 1)",                 NO_PROJECT_DIR,       expect_score=0,  expect_passed=False),
        run("stub only — dir exists, tiny file (5)",   STUB_ONLY,            expect_score=5,  expect_passed=False),
        run("partial — 3 callbacks, 1 fn, no sysctl (42)", PARTIAL,          expect_score=42, expect_passed=False),
        run("define after include — C3=0 (80/100)",   DEFINE_AFTER_INCLUDE, expect_score=80, expect_passed=True),
        run("full correct, no binary (95/100)",       FULL_NO_BINARY,       expect_score=95, expect_passed=True),
        run("full correct with binary (100/100)",     FULL_WITH_BINARY,     expect_score=100, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
