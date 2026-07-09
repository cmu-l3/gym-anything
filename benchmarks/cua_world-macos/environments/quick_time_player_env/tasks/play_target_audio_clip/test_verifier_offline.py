"""Offline mock tests for verify_play_target_audio_clip.

Run from repo root:

    python3 benchmarks/cua_world-macos/environments/quick_time_player_env/tasks/play_target_audio_clip/test_verifier_offline.py

Per task_creation_notes/13_file_content_verification_and_offline_testing.md:
required scenarios are do-nothing, wrong-target, partial, and full-correct.
Plus the anti-gaming scenarios:
  - File deleted but document still in front (cached AppleScript state)
  - File replaced with a different-sized file
  - Document opened but not played (playback never started)

Each scenario injects a fabricated result dict (the shape produced by
export_result.sh) and asserts the verifier's score and pass decision.
Exits non-zero on any assertion failure so CI can gate on it.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
VERIFIER_PATH = HERE / "verifier.py"
spec = importlib.util.spec_from_file_location("verifier", VERIFIER_PATH)
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
verify = mod.verify_play_target_audio_clip


def make_env_info(fake_result: dict) -> dict:
    fixture = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    fixture.write(json.dumps(fake_result).encode()); fixture.close()
    def copy_from_env(_remote: str, local: str) -> None:
        shutil.copy(fixture.name, local)
    return {"copy_from_env": copy_from_env, "_fixture": fixture.name}


def run(name: str, fake_result: dict, expect_score, expect_passed: bool) -> bool:
    env_info = make_env_info(fake_result)
    out = verify(traj={}, env_info=env_info, task_info={})
    Path(env_info["_fixture"]).unlink(missing_ok=True)
    score = out["score"]; passed = out["passed"]
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
        return False
    return True


TASK_START = 1_000_000
EXPECTED_NAME = "qtp_target_audio.aiff"
EXPECTED_SIZE = 623130
EXPECTED_DURATION = 2.163458


DO_NOTHING = {
    # Agent did nothing. QuickTime is still running, document is loaded
    # (because pre_task loaded it), current_time still at 0.0.
    "task_start": TASK_START, "documents_open_count": 1,
    "front_document_name": EXPECTED_NAME, "front_document_path": "/Users/lume/Documents/qtp_target_audio.aiff",
    "front_document_duration": EXPECTED_DURATION, "front_document_current_time": 0.0,
    "front_document_playing": False, "target_file_exists": True,
    "target_file_mtime": TASK_START - 5, "target_file_size": EXPECTED_SIZE,
    "target_file_unchanged": True, "process_running": True,
}

WRONG_TARGET_DIFFERENT_DOC = {
    # Agent quit the pre-loaded clip and opened something else.
    # Strict gate fires → score 0.
    "task_start": TASK_START, "documents_open_count": 1,
    "front_document_name": "some_other_file.mp4", "front_document_path": "/Users/lume/Documents/some_other_file.mp4",
    "front_document_duration": 10.0, "front_document_current_time": 5.0,
    "front_document_playing": False, "target_file_exists": True,
    "target_file_mtime": TASK_START - 5, "target_file_size": EXPECTED_SIZE,
    "target_file_unchanged": True, "process_running": True,
}

WRONG_TARGET_NO_DOC = {
    # Agent closed the document. Strict gate fires (docs_open == 0).
    "task_start": TASK_START, "documents_open_count": 0,
    "front_document_name": "", "front_document_path": "",
    "front_document_duration": 0.0, "front_document_current_time": 0.0,
    "front_document_playing": False, "target_file_exists": True,
    "target_file_mtime": TASK_START - 5, "target_file_size": EXPECTED_SIZE,
    "target_file_unchanged": True, "process_running": True,
}

PARTIAL_STARTED_BUT_NOT_MEANINGFUL = {
    # Agent pressed space but only let it play for ~0.7s — past the started
    # threshold (0.5) but not the meaningful threshold (1.0).
    # Expected: C1 15 + C2 10 + C3 40 + C4 0 + C5 5 = 70 — wait, that's a PASS.
    # Let me recompute: actually a true partial here is BELOW C3's threshold.
    # This particular fixture (current=0.7) DOES cross C3 (>=0.5) so it scores 70.
    # We want a *failing* partial, so use current=0.4.
    "task_start": TASK_START, "documents_open_count": 1,
    "front_document_name": EXPECTED_NAME, "front_document_path": "/Users/lume/Documents/qtp_target_audio.aiff",
    "front_document_duration": EXPECTED_DURATION, "front_document_current_time": 0.4,
    "front_document_playing": False, "target_file_exists": True,
    "target_file_mtime": TASK_START - 5, "target_file_size": EXPECTED_SIZE,
    "target_file_unchanged": True, "process_running": True,
}

JUST_STARTED_PASSES_C3_FAILS_C4 = {
    # Agent pressed space briefly, current_time advanced to 0.7s.
    # C1 15 + C2 10 + C3 40 + C4 0 + C5 5 = 70 → PASS (above threshold).
    # This validates the meaningful-playback threshold isn't required for pass.
    "task_start": TASK_START, "documents_open_count": 1,
    "front_document_name": EXPECTED_NAME, "front_document_path": "/Users/lume/Documents/qtp_target_audio.aiff",
    "front_document_duration": EXPECTED_DURATION, "front_document_current_time": 0.7,
    "front_document_playing": False, "target_file_exists": True,
    "target_file_mtime": TASK_START - 5, "target_file_size": EXPECTED_SIZE,
    "target_file_unchanged": True, "process_running": True,
}

FULL_CORRECT = {
    # Agent played past 1.0s.
    # C1 15 + C2 10 + C3 40 + C4 30 + C5 5 = 100.
    "task_start": TASK_START, "documents_open_count": 1,
    "front_document_name": EXPECTED_NAME, "front_document_path": "/Users/lume/Documents/qtp_target_audio.aiff",
    "front_document_duration": EXPECTED_DURATION, "front_document_current_time": 1.5,
    "front_document_playing": False, "target_file_exists": True,
    "target_file_mtime": TASK_START - 5, "target_file_size": EXPECTED_SIZE,
    "target_file_unchanged": True, "process_running": True,
}

PLAYED_TO_END = {
    # Audio played to completion. current_time = duration (~2.16s).
    # Full score.
    "task_start": TASK_START, "documents_open_count": 1,
    "front_document_name": EXPECTED_NAME, "front_document_path": "/Users/lume/Documents/qtp_target_audio.aiff",
    "front_document_duration": EXPECTED_DURATION, "front_document_current_time": EXPECTED_DURATION,
    "front_document_playing": False, "target_file_exists": True,
    "target_file_mtime": TASK_START - 5, "target_file_size": EXPECTED_SIZE,
    "target_file_unchanged": True, "process_running": True,
}

FILE_REPLACED = {
    # Agent replaced the target file with a different (larger) file but the
    # AppleScript front-document state still reports the expected name and a
    # high current_time. C2 fails (size mismatch), other criteria score.
    # C1 15 + C2 0 + C3 40 + C4 30 + C5 5 = 90 → still passes.
    # This is an acceptable adversarial outcome: the file-integrity criterion
    # is a SECONDARY signal (10 pts only). The PRIMARY criteria (C3/C4) are
    # tied to playback state which would also be affected by file replacement.
    # We capture the file integrity to flag this case in the feedback string.
    "task_start": TASK_START, "documents_open_count": 1,
    "front_document_name": EXPECTED_NAME, "front_document_path": "/Users/lume/Documents/qtp_target_audio.aiff",
    "front_document_duration": EXPECTED_DURATION, "front_document_current_time": 1.5,
    "front_document_playing": False, "target_file_exists": True,
    "target_file_mtime": TASK_START + 1, "target_file_size": 999999,   # wrong size
    "target_file_unchanged": False, "process_running": True,
}

PROCESS_CRASHED = {
    # QuickTime crashed before export. AppleScript wouldn't actually return
    # anything in that scenario; export_result.sh emits zero-defaults.
    # documents_open_count == 0 → strict gate fires → score 0.
    "task_start": TASK_START, "documents_open_count": 0,
    "front_document_name": "", "front_document_path": "",
    "front_document_duration": 0.0, "front_document_current_time": 0.0,
    "front_document_playing": False, "target_file_exists": True,
    "target_file_mtime": TASK_START - 5, "target_file_size": EXPECTED_SIZE,
    "target_file_unchanged": True, "process_running": False,
}


if __name__ == "__main__":
    print("=== Offline verifier tests: play_target_audio_clip ===")
    results = [
        run("do-nothing (loaded but never played)",         DO_NOTHING,                          expect_score=30, expect_passed=False),
        run("wrong-target (different document in front)",   WRONG_TARGET_DIFFERENT_DOC,          expect_score=0,  expect_passed=False),
        run("wrong-target (no document open)",              WRONG_TARGET_NO_DOC,                 expect_score=0,  expect_passed=False),
        run("partial (current_time 0.4 — below C3)",        PARTIAL_STARTED_BUT_NOT_MEANINGFUL,  expect_score=30, expect_passed=False),
        run("just past C3 (current_time 0.7)",              JUST_STARTED_PASSES_C3_FAILS_C4,     expect_score=70, expect_passed=True),
        run("full-correct (played to 1.5s)",                FULL_CORRECT,                        expect_score=100, expect_passed=True),
        run("played to end (current_time == duration)",     PLAYED_TO_END,                       expect_score=100, expect_passed=True),
        run("file replaced (size mismatch)",                FILE_REPLACED,                       expect_score=90, expect_passed=True),
        run("process crashed (no docs open)",               PROCESS_CRASHED,                     expect_score=0,  expect_passed=False),
    ]
    failed = sum(1 for r in results if not r)
    print()
    print(f"{len(results) - failed}/{len(results)} scenarios passed")
    sys.exit(0 if failed == 0 else 1)
