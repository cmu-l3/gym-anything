"""Offline mock tests for verify_audit_macfuse_install.

Per task_creation_notes/13_file_content_verification_and_offline_testing.md
(Gap 2) — mock copy_from_env by writing a synthetic export-result dict to the
local path the verifier opens.

Required scenarios: do-nothing, wrong-target, partial, full-correct, plus the
strategy-enumeration scenarios from Anti-Pattern 13 (mass-guess without
probing, fabrication with extra keys, stale report).

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/macfuse_env/tasks/audit_macfuse_install/test_verifier_offline.py
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
verify = mod.verify_audit_macfuse_install


# Authoritative ground truth captured live on use.computer dev fleet against
# macFUSE 4.10.2 install (2026-05). Per-sandbox install times are *real*
# Unix epochs from `pkgutil --pkg-info` for the two macFUSE pkg components.
GT_CORE_INSTALL_TIME = 1779076645   # sandbox-specific; the install time of the .pkg in the probed sandbox
GT_PREFPANE_INSTALL_TIME = 1779076645

BASE_EXPORT = {
    "task_start": 1779076600,
    "gt_bundle_version": "4.10.2",
    "gt_bundle_identifier": "io.macfuse.filesystems.fs.macfuse",
    "gt_pkg_core_version": "4.10.2",
    "gt_core_pkg_install_time": GT_CORE_INSTALL_TIME,
    "gt_prefpane_pkg_install_time": GT_PREFPANE_INSTALL_TIME,
    "gt_kext_currently_loaded": False,
    "gt_mount_helper_path": "/Library/Filesystems/macfuse.fs/Contents/Resources/mount_macfuse",
    "gt_supported_macos_versions_count": 13,
    "gt_libfuse_dylib_count": 4,
    "gt_prefpane_installed": True,
}


def make_env_info(fake_result: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(fake_result).encode())
    fixture.close()

    def copy_from_env(_remote: str, local: str) -> None:
        shutil.copy(fixture.name, local)

    return {"copy_from_env": copy_from_env, "_fixture": fixture.name}


def run(name: str, fake_result: dict, expect_score, expect_passed: bool) -> bool:
    env_info = make_env_info(fake_result)
    task_info = {"metadata": {"install_time_tolerance_sec": 2, "pass_threshold": 70}}
    out = verify(traj={}, env_info=env_info, task_info=task_info)
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
    status = "PASS" if (score_ok and pass_ok) else "FAIL"
    print(f"[{status}] {name}: got score={score} passed={passed} "
          f"(expected score={expect_desc} passed={expect_passed})")
    if not (score_ok and pass_ok):
        print(f"    subscores: {out['subscores']}")
        print(f"    feedback:  {out['feedback']}")
    return score_ok and pass_ok


# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

# Do-nothing: no report at all.
DO_NOTHING = {
    **BASE_EXPORT,
    "report_exists": False, "report_fresh": False, "report_valid_json": False,
    "agent_bundle_version": None, "agent_bundle_identifier": None,
    "agent_pkg_core_version": None,
    "agent_core_pkg_install_time": None, "agent_prefpane_pkg_install_time": None,
    "agent_kext_currently_loaded": None, "agent_mount_helper_path": None,
    "agent_supported_macos_versions_count": None, "agent_libfuse_dylib_count": None,
    "agent_prefpane_installed": None,
    "extra_keys": [], "mentions_macfuse": False,
}

# Wrong target (strict gate): agent wrote a JSON about a totally different
# component (e.g. NTFS driver) with no mention of macFUSE at all.
WRONG_TARGET = {
    **BASE_EXPORT,
    "report_exists": True, "report_fresh": True, "report_valid_json": True,
    "agent_bundle_version": "5.0.0",
    "agent_bundle_identifier": "com.tuxera.ntfs",
    "agent_pkg_core_version": None,
    "agent_core_pkg_install_time": None,
    "agent_prefpane_pkg_install_time": None,
    "agent_kext_currently_loaded": True,
    "agent_mount_helper_path": "/sbin/mount_ntfs",
    "agent_supported_macos_versions_count": 1,
    "agent_libfuse_dylib_count": 0,
    "agent_prefpane_installed": False,
    "extra_keys": ["ntfs_driver_version"],
    "mentions_macfuse": False,    # ← gate fires here
}

# Mass-guess without probing: agent fills in all public facts correctly
# (version, identifier, paths, counts, kext_loaded=false) but cannot fill in
# the per-sandbox install_time values. Expected score = 60, below pass
# threshold (70). This is the key adversarial scenario.
MASS_GUESS = {
    **BASE_EXPORT,
    "report_exists": True, "report_fresh": True, "report_valid_json": True,
    "agent_bundle_version": "4.10.2",
    "agent_bundle_identifier": "io.macfuse.filesystems.fs.macfuse",
    "agent_pkg_core_version": "4.10.2",
    "agent_core_pkg_install_time": 0,            # guess fails — wrong by years
    "agent_prefpane_pkg_install_time": 0,        # guess fails
    "agent_kext_currently_loaded": False,
    "agent_mount_helper_path": "/Library/Filesystems/macfuse.fs/Contents/Resources/mount_macfuse",
    "agent_supported_macos_versions_count": 13,
    "agent_libfuse_dylib_count": 4,
    "agent_prefpane_installed": True,
    "extra_keys": [], "mentions_macfuse": True,
}

# Partial completion: agent did probe and got SOME values right (file + 5
# easy fields, including ONE install_time) but missed the other install_time
# and got versions_count wrong. Should be > 0 but < pass_threshold.
# 10 + 5 + 5 + 5 + 20 + 0 + 5 + 5 + 0 + 5 + 10 = 70 — RIGHT at threshold
# Reduce: also miss kext_loaded and prefpane_installed.
# 10 + 5 + 5 + 5 + 20 + 0 + 0 + 5 + 0 + 5 + 0 = 55.
PARTIAL = {
    **BASE_EXPORT,
    "report_exists": True, "report_fresh": True, "report_valid_json": True,
    "agent_bundle_version": "4.10.2",
    "agent_bundle_identifier": "io.macfuse.filesystems.fs.macfuse",
    "agent_pkg_core_version": "4.10.2",
    "agent_core_pkg_install_time": GT_CORE_INSTALL_TIME,     # got one
    "agent_prefpane_pkg_install_time": 0,                    # missed
    "agent_kext_currently_loaded": True,                     # wrong (it's False)
    "agent_mount_helper_path": "/Library/Filesystems/macfuse.fs/Contents/Resources/mount_macfuse",
    "agent_supported_macos_versions_count": 11,              # off by 2
    "agent_libfuse_dylib_count": 4,
    "agent_prefpane_installed": False,                       # wrong (it's True)
    "extra_keys": [], "mentions_macfuse": True,
}

# Full-correct: agent probed everything correctly.
FULL_CORRECT = {
    **BASE_EXPORT,
    "report_exists": True, "report_fresh": True, "report_valid_json": True,
    "agent_bundle_version": "4.10.2",
    "agent_bundle_identifier": "io.macfuse.filesystems.fs.macfuse",
    "agent_pkg_core_version": "4.10.2",
    "agent_core_pkg_install_time": GT_CORE_INSTALL_TIME,
    "agent_prefpane_pkg_install_time": GT_PREFPANE_INSTALL_TIME,
    "agent_kext_currently_loaded": False,
    "agent_mount_helper_path": "/Library/Filesystems/macfuse.fs/Contents/Resources/mount_macfuse",
    "agent_supported_macos_versions_count": 13,
    "agent_libfuse_dylib_count": 4,
    "agent_prefpane_installed": True,
    "extra_keys": [], "mentions_macfuse": True,
}

# Full-correct + tolerance: agent's install_time is off by exactly the tolerance.
FULL_CORRECT_TOLERANCE = {
    **FULL_CORRECT,
    "agent_core_pkg_install_time": GT_CORE_INSTALL_TIME + 2,
    "agent_prefpane_pkg_install_time": GT_PREFPANE_INSTALL_TIME - 2,
}

# Install_time just outside tolerance — should NOT credit.
INSTALL_TIME_OUT_OF_TOLERANCE = {
    **FULL_CORRECT,
    "agent_core_pkg_install_time": GT_CORE_INSTALL_TIME + 3,
    "agent_prefpane_pkg_install_time": GT_PREFPANE_INSTALL_TIME - 3,
}
# Score: 10 + 5 + 5 + 5 + 0 + 0 + 5 + 5 + 10 + 5 + 10 = 60 (< 70, fails)

# Stale report (mtime predates task_start): C1 gets 5 instead of 10.
STALE_REPORT = {
    **FULL_CORRECT,
    "report_fresh": False,
}
# 5 + 5 + 5 + 5 + 20 + 20 + 5 + 5 + 10 + 5 + 10 = 95 (still passes)

# Bool-as-string: agent wrote "True"/"False" as strings instead of JSON
# booleans. The normalizer accepts case-insensitive 'true'/'false'.
BOOL_AS_STRING = {
    **FULL_CORRECT,
    "agent_kext_currently_loaded": "false",
    "agent_prefpane_installed": "TRUE",
}

# Int-as-string: same idea — JSON-stringified numbers should still match.
INT_AS_STRING = {
    **FULL_CORRECT,
    "agent_supported_macos_versions_count": "13",
    "agent_libfuse_dylib_count": "4",
    "agent_core_pkg_install_time": str(GT_CORE_INSTALL_TIME),
    "agent_prefpane_pkg_install_time": str(GT_PREFPANE_INSTALL_TIME),
}


if __name__ == "__main__":
    print("=== Offline verifier tests: audit_macfuse_install ===")
    results = [
        run("do-nothing",                                DO_NOTHING,                expect_score=0,   expect_passed=False),
        run("wrong-target (strict gate fires)",          WRONG_TARGET,              expect_score=0,   expect_passed=False),
        run("mass-guess without probing (60/100)",       MASS_GUESS,                expect_score=60,  expect_passed=False),
        run("partial (55/100)",                          PARTIAL,                   expect_score=55,  expect_passed=False),
        run("full-correct (100/100)",                    FULL_CORRECT,              expect_score=100, expect_passed=True),
        run("full-correct within ±2s tolerance",         FULL_CORRECT_TOLERANCE,    expect_score=100, expect_passed=True),
        run("install_time off by 3s (60/100)",           INSTALL_TIME_OUT_OF_TOLERANCE, expect_score=60, expect_passed=False),
        run("stale report (95/100)",                     STALE_REPORT,              expect_score=95,  expect_passed=True),
        run("bool-as-string accepted",                   BOOL_AS_STRING,            expect_score=100, expect_passed=True),
        run("int-as-string accepted",                    INT_AS_STRING,             expect_score=100, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
