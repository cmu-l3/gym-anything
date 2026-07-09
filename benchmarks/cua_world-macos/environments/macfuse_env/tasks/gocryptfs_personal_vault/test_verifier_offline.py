"""Offline mock tests for verify_gocryptfs_personal_vault.

Per task_creation_notes/13_file_content_verification_and_offline_testing.md.

Scoring recap (100 pts, pass at 70):
  C1   5 pts  brew installed
  C2  15 pts  gocryptfs binary installed
  C3  20 pts  vault.enc/ exists WITH gocryptfs.conf (proof -init ran)
  C4   5 pts  vault.plain/ exists
  C5  20 pts  mount_vault.sh (exists+exec+gocryptfs)
  C6   5 pts  umount_vault.sh (exists+exec+umount/diskutil)
  C7  20 pts  LaunchAgent plist (4 sub-conds × 5 pts)
  C8  10 pts  launchctl list contains label

Notable: "no LaunchAgent" path (C1+C2+C3+C4+C5+C6 = 70) is exactly at
threshold — documented as intentional in the README.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/macfuse_env/tasks/gocryptfs_personal_vault/test_verifier_offline.py
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
verify = mod.verify_gocryptfs_personal_vault

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


def _all_false() -> dict:
    return {
        "brew_installed": False, "brew_path": None,
        "gocryptfs_installed": False, "gocryptfs_path": None,
        "vault_enc_exists": False, "vault_enc_conf_exists": False,
        "vault_plain_exists": False,
        "mount_script_exists": False, "mount_script_executable": False,
        "mount_script_has_gocryptfs": False,
        "umount_script_exists": False, "umount_script_executable": False,
        "umount_script_has_unmount": False,
        "plist_exists": False, "plist_parses": False, "plist_label_matches": False,
        "plist_run_at_load_true": False, "plist_log_paths_set": False,
        "plist_program_args_invokes_mount": False,
        "launch_agent_loaded": False,
    }


def _full_plist() -> dict:
    return {
        "plist_exists": True, "plist_parses": True, "plist_label_matches": True,
        "plist_run_at_load_true": True, "plist_log_paths_set": True,
        "plist_program_args_invokes_mount": True,
    }


def _full_correct() -> dict:
    return {
        "brew_installed": True, "brew_path": "/opt/homebrew/bin/brew",
        "gocryptfs_installed": True, "gocryptfs_path": "/opt/homebrew/bin/gocryptfs",
        "vault_enc_exists": True, "vault_enc_conf_exists": True,
        "vault_plain_exists": True,
        "mount_script_exists": True, "mount_script_executable": True,
        "mount_script_has_gocryptfs": True,
        "umount_script_exists": True, "umount_script_executable": True,
        "umount_script_has_unmount": True,
        **_full_plist(),
        "launch_agent_loaded": True,
    }


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

DO_NOTHING = None  # result file missing → 0

DO_NOTHING_EMPTY = _all_false()  # export ran, agent did nothing → 0

# vault.enc dir exists but NO gocryptfs.conf — agent mkdir'd without -init
# C1=5, C2=15, C3=0, C4=5 → 25 (fail)
MKDIR_NO_INIT = {**_all_false(),
                 "brew_installed": True, "brew_path": "/opt/homebrew/bin/brew",
                 "gocryptfs_installed": True, "gocryptfs_path": "/opt/homebrew/bin/gocryptfs",
                 "vault_enc_exists": True, "vault_enc_conf_exists": False,
                 "vault_plain_exists": True}

# install + init + dirs, but no scripts, no plist, no launchctl
# C1=5, C2=15, C3=20, C4=5 → 45 (fail)
DIRS_ONLY = {**_all_false(),
             "brew_installed": True, "brew_path": "/opt/homebrew/bin/brew",
             "gocryptfs_installed": True, "gocryptfs_path": "/opt/homebrew/bin/gocryptfs",
             "vault_enc_exists": True, "vault_enc_conf_exists": True,
             "vault_plain_exists": True}

# "no-launchagent" path: all scripts done, no plist, no launchctl load
# C1+C2+C3+C4+C5+C6 = 5+15+20+5+20+5 = 70 (exactly at threshold → passes)
NO_LAUNCHAGENT = {**_full_correct(),
                  "plist_exists": False, "plist_parses": False, "plist_label_matches": False,
                  "plist_run_at_load_true": False, "plist_log_paths_set": False,
                  "plist_program_args_invokes_mount": False,
                  "launch_agent_loaded": False}

# Plist present but only 2 sub-conditions correct (label+RunAtLoad):
# C7 = 5 + 5 = 10; C8=0 (no launchctl)
# Total: 5+15+20+5+20+5+10+0 = 80 (pass)
PLIST_PARTIAL = {**_full_correct(),
                 "plist_log_paths_set": False,
                 "plist_program_args_invokes_mount": False,
                 "launch_agent_loaded": False}
# C7: label+runatload=10, log_paths=0, prog_args=0 → 10. C8=0. Total=80.

# Full correct: 100 (pass)
FULL = _full_correct()


if __name__ == "__main__":
    print("=== Offline verifier tests: gocryptfs_personal_vault ===")
    results = [
        run("do-nothing (result file missing)",           DO_NOTHING,       expect_score=0,   expect_passed=False),
        run("do-nothing (export ran, empty)",             DO_NOTHING_EMPTY, expect_score=0,   expect_passed=False),
        run("mkdir without -init — no gocryptfs.conf (25)", MKDIR_NO_INIT, expect_score=25,  expect_passed=False),
        run("dirs only, no scripts (45/100)",             DIRS_ONLY,        expect_score=45,  expect_passed=False),
        run("no-launchagent path (70 = threshold)",       NO_LAUNCHAGENT,   expect_score=70,  expect_passed=True),
        run("plist partial (2/4 sub-conds, 80/100)",      PLIST_PARTIAL,    expect_score=80,  expect_passed=True),
        run("full correct (100/100)",                     FULL,             expect_score=100, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
