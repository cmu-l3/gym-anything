"""Offline mock tests for verify_sshfs_home_nas_setup.

Per task_creation_notes/13_file_content_verification_and_offline_testing.md
(Gap 2) — mock copy_from_env by writing a synthetic export-result dict.

Scenarios cover: do-nothing, partial (toolchain only, no config), full,
and key Anti-Pattern 13 strategies (scripts-only-no-tools, missing-one-option).

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/macfuse_env/tasks/sshfs_home_nas_setup/test_verifier_offline.py
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
verify = mod.verify_sshfs_home_nas_setup


def make_env_info(fake_result: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(fake_result).encode())
    fixture.close()

    def copy_from_env(_remote: str, local: str) -> None:
        shutil.copy(fixture.name, local)

    return {"copy_from_env": copy_from_env, "_fixture": fixture.name}


def make_env_info_missing() -> dict:
    def copy_from_env(_remote: str, _local: str) -> None:
        raise FileNotFoundError("No result file — agent did nothing")

    return {"copy_from_env": copy_from_env}


TASK_INFO = {"metadata": {"pass_threshold": 70}}


def run(name: str, fake_result, expect_score, expect_passed: bool) -> bool:
    if fake_result is None:
        env_info = make_env_info_missing()
    else:
        env_info = make_env_info(fake_result)
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
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {name}: score={score} passed={passed} "
          f"(expected score={expect_desc} passed={expect_passed})")
    if not ok:
        print(f"    subscores: {out['subscores']}")
        print(f"    feedback:  {out['feedback'][:300]}")
    return ok


# ---------------------------------------------------------------------------
# Base state helpers
# ---------------------------------------------------------------------------

def _all_false() -> dict:
    return {
        "brew_installed": False,
        "brew_binary_path": None,
        "gromgit_tap_added": False,
        "sshfs_binary_path": None,
        "mount_point_exists": False,
        "ssh_host_configured": False,
        "ssh_hostname_correct": False,
        "ssh_user_correct": False,
        "ssh_identity_file_set": False,
        "mount_script_exists": False,
        "mount_script_executable": False,
        "mount_script_has_volname": False,
        "mount_script_has_reconnect": False,
        "mount_script_has_defer_permissions": False,
        "launchagent_plist_exists": False,
        "launchagent_label_correct": False,
        "launchagent_has_runatload": False,
        "launchagent_has_keepalive": False,
        "launchagent_has_logging": False,
    }


def _full_correct() -> dict:
    return {
        "brew_installed": True,
        "brew_binary_path": "/opt/homebrew/bin/brew",
        "gromgit_tap_added": True,
        "sshfs_binary_path": "/opt/homebrew/bin/sshfs",
        "mount_point_exists": True,
        "ssh_host_configured": True,
        "ssh_hostname_correct": True,
        "ssh_user_correct": True,
        "ssh_identity_file_set": True,
        "mount_script_exists": True,
        "mount_script_executable": True,
        "mount_script_has_volname": True,
        "mount_script_has_reconnect": True,
        "mount_script_has_defer_permissions": True,
        "launchagent_plist_exists": True,
        "launchagent_label_correct": True,
        "launchagent_has_runatload": True,
        "launchagent_has_keepalive": True,
        "launchagent_has_logging": True,
    }


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

DO_NOTHING = None  # copy_from_env raises → score 0

DO_NOTHING_EMPTY = _all_false()  # export ran, agent did nothing

# Toolchain only (brew + tap + sshfs): C1+C2+C3 = 35, rest 0 → 35 (fail)
TOOLCHAIN_ONLY = {**_all_false(),
                  "brew_installed": True, "brew_binary_path": "/opt/homebrew/bin/brew",
                  "gromgit_tap_added": True,
                  "sshfs_binary_path": "/opt/homebrew/bin/sshfs"}

# Config only (no toolchain): C4+C5+C6+C7 = 5+20+25+15 = 65 (fail — below 70)
CONFIG_ONLY = {**_all_false(),
               "mount_point_exists": True,
               "ssh_host_configured": True, "ssh_hostname_correct": True,
               "ssh_user_correct": True, "ssh_identity_file_set": True,
               "mount_script_exists": True, "mount_script_executable": True,
               "mount_script_has_volname": True, "mount_script_has_reconnect": True,
               "mount_script_has_defer_permissions": True,
               "launchagent_plist_exists": True, "launchagent_label_correct": True,
               "launchagent_has_runatload": True, "launchagent_has_keepalive": True,
               "launchagent_has_logging": True}
# Score: 0+0+0+5+20+25+15 = 65 (fail)

# Missing defer_permissions: everything else correct → 100 - 5 = 95 (pass)
MISSING_DEFER = {**_full_correct(), "mount_script_has_defer_permissions": False}

# Full correct: 100 (pass)
FULL_CORRECT = _full_correct()


if __name__ == "__main__":
    print("=== Offline verifier tests: sshfs_home_nas_setup ===")
    results = [
        run("do-nothing (result file missing)",          DO_NOTHING,       expect_score=0,         expect_passed=False),
        run("do-nothing (export ran, empty)",            DO_NOTHING_EMPTY, expect_score=0,         expect_passed=False),
        run("toolchain only (35/100)",                   TOOLCHAIN_ONLY,   expect_score=35,        expect_passed=False),
        run("config only — no tools (65/100)",           CONFIG_ONLY,      expect_score=65,        expect_passed=False),
        run("full minus defer_permissions (95/100)",     MISSING_DEFER,    expect_score=95,        expect_passed=True),
        run("full correct (100/100)",                    FULL_CORRECT,     expect_score=100,       expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
