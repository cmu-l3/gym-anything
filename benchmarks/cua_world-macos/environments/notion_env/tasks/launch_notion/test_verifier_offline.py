"""Offline mock tests for verify_notion_running.

The smoke verifier uses `exec_capture` (not `copy_from_env`), so we mock the
command dispatch — see Gap 4 in
`extras/research/task_generation/propose_and_amplify/memory/task_creation_notes/13_file_content_verification_and_offline_testing.md`.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/notion_env/tasks/launch_notion/test_verifier_offline.py
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verifier", HERE / "verifier.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
verify = mod.verify_notion_running


def make_exec_capture(process_running: bool, window_registered: bool):
    """Return an exec_capture function that simulates pgrep + lsappinfo
    output matching the requested (process_running, window_registered) pair.
    """
    def exec_capture(cmd: str) -> str:
        if "pgrep" in cmd and "Notion" in cmd:
            # Simulated pid output for `pgrep -x Notion`
            return "12345\n" if process_running else ""
        if "lsappinfo" in cmd:
            if window_registered:
                # Realistic lsappinfo list line. Helpers would also appear
                # but the verifier's grep is specifically for "Notion" with
                # quoted, word-boundary semantics.
                return (
                    '   2) "Notion" ASN:0x0-0x12345: /Applications/Notion.app\n'
                )
            return ""
        return ""
    return exec_capture


def run(name: str, process_running: bool, window_registered: bool,
        expect_score: int, expect_passed: bool) -> bool:
    env_info = {"exec_capture": make_exec_capture(process_running, window_registered)}
    out = verify(traj={}, env_info=env_info, task_info={})
    score = out["score"]
    passed = out["passed"]
    ok = score == expect_score and passed == expect_passed
    status = "PASS" if ok else "FAIL"
    print(
        f"[{status}] {name}: got score={score} passed={passed} "
        f"(expected score={expect_score} passed={expect_passed})"
    )
    if not ok:
        print(f"    feedback: {out['feedback']}")
    return ok


if __name__ == "__main__":
    print("=== Offline verifier tests: launch_notion ===")
    results = [
        run("do-nothing (Notion not running)",
            process_running=False, window_registered=False,
            expect_score=0, expect_passed=False),
        run("process running but window not registered (partial)",
            process_running=True, window_registered=False,
            expect_score=50, expect_passed=False),
        run("window registered without process (anomalous — defensive)",
            process_running=False, window_registered=True,
            expect_score=0, expect_passed=False),
        run("full launch (process running, window registered)",
            process_running=True, window_registered=True,
            expect_score=100, expect_passed=True),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
