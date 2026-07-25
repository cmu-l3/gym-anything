"""Offline mock tests for verify_macfuse_installed.

The smoke verifier uses `exec_capture` (Gap 4 in
task_creation_notes/13_file_content_verification_and_offline_testing.md), so
we mock command dispatch.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/macfuse_env/tasks/launch_macfuse/test_verifier_offline.py
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verifier", HERE / "verifier.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
verify = mod.verify_macfuse_installed


def make_exec_capture(
    bundle_present: bool, version: str | None, mount_helper_present: bool
):
    def exec_capture(cmd: str) -> str:
        if "test -d /Library/Filesystems/macfuse.fs" in cmd:
            return "yes\n" if bundle_present else "no\n"
        if "defaults read" in cmd and "CFBundleShortVersionString" in cmd:
            return (version or "") + "\n"
        if "test -x" in cmd and "mount_macfuse" in cmd:
            return "yes\n" if mount_helper_present else "no\n"
        return ""
    return exec_capture


def run(name: str, bundle: bool, version: str | None, helper: bool,
        expect_score: int, expect_passed: bool) -> bool:
    env_info = {"exec_capture": make_exec_capture(bundle, version, helper)}
    out = verify(traj={}, env_info=env_info, task_info={})
    ok = out["score"] == expect_score and out["passed"] == expect_passed
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {name}: got score={out['score']} passed={out['passed']} "
          f"(expected score={expect_score} passed={expect_passed})")
    if not ok:
        print(f"    feedback: {out['feedback']}")
    return ok


if __name__ == "__main__":
    print("=== Offline verifier tests: launch_macfuse ===")
    results = [
        run("do-nothing (install failed, nothing on disk)",
            bundle=False, version=None, helper=False,
            expect_score=0, expect_passed=False),
        run("bundle only (defaults read failed, no helper)",
            bundle=True, version=None, helper=False,
            expect_score=40, expect_passed=False),
        run("bundle + version (helper missing)",
            bundle=True, version="4.10.2", helper=False,
            expect_score=70, expect_passed=False),
        run("bundle + helper (version unknown)",
            bundle=True, version="unknown", helper=True,
            expect_score=70, expect_passed=False),
        run("full install (all three present)",
            bundle=True, version="4.10.2", helper=True,
            expect_score=100, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
