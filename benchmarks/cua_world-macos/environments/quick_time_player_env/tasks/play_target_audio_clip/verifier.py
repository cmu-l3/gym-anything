"""Verifier for play_target_audio_clip.

Scoring (100 points, pass at 60):
- 15 pts  C1  Front document is the expected target (name match exactly).
              Strict gate: if no document is open or the wrong name is in
              front, score=0 immediately (Pattern #2 wrong-target).
- 10 pts  C2  Target file at ~/Documents/qtp_target_audio.aiff still exists
              and is unchanged (size matches the original 623130 bytes).
              Prevents the agent from "passing" by replacing the audio file
              with a longer file (no-op for this task — the agent can't
              shorten the way to a high current_time by replacing the file
              because the playing duration would no longer match the expected
              ~2.16s reference, but we score the existence/integrity
              separately as a safety net).
- 40 pts  C3  current_time advanced past 0.5 seconds (playback started).
              Binary: 40 if >= 0.5, else 0.
- 30 pts  C4  current_time reached at least 1.0 seconds (meaningful play).
              Binary: 30 if >= 1.0, else 0.
- 5  pts  C5  QuickTime process still running at task end (no crash).

Partial-only upper bound (no full credit on any criterion):
  This task uses binary criteria so "partial" means "got C1+C2+C5 but not C3
  or C4": 15+10+0+0+5 = 30. Pass threshold 60 > 30 → safe per
  Anti-Pattern #4 in task_creation_notes/14_task_design_antipatterns.md.

Strict wrong-target gate (Pattern #2):
  Any scenario where (documents_open_count == 0) OR
  (front_document_name != "qtp_target_audio.aiff") returns score=0 directly
  WITHOUT awarding any criteria.

Read pattern: copy_from_env(/tmp/play_target_audio_clip_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

EXPECTED_NAME = "qtp_target_audio.aiff"
EXPECTED_SIZE = 623130          # bytes; matches /System/Library/Sounds/Funk.aiff
EXPECTED_DURATION = 2.163458    # seconds
PLAY_STARTED_THRESHOLD = 0.5
MEANINGFUL_PLAY_THRESHOLD = 1.0
PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/play_target_audio_clip_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "front_document_match": 0,
        "target_file_integrity": 0,
        "playback_started": 0,
        "meaningful_playback": 0,
        "process_alive": 0,
    }


def verify_play_target_audio_clip(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            logger.warning("copy_from_env failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Could not retrieve result file from sandbox: {exc}",
                    "subscores": _empty_subscores()}
        try:
            with open(local_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            logger.warning("result JSON parse failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Export produced unparseable JSON: {exc}",
                    "subscores": _empty_subscores()}
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    docs_open = int(data.get("documents_open_count") or 0)
    front_name = (data.get("front_document_name") or "").strip()
    current_time = float(data.get("front_document_current_time") or 0.0)
    duration = float(data.get("front_document_duration") or 0.0)
    target_exists = bool(data.get("target_file_exists"))
    target_unchanged = bool(data.get("target_file_unchanged"))
    target_size = int(data.get("target_file_size") or 0)
    process_running = bool(data.get("process_running"))

    # ---- Strict wrong-target gate (Pattern #2) ----
    if docs_open == 0:
        return {"score": 0, "passed": False,
                "feedback": "No document open in QuickTime Player. The target audio file "
                            "must remain loaded as the front document for verification.",
                "subscores": _empty_subscores()}
    if front_name != EXPECTED_NAME:
        return {"score": 0, "passed": False,
                "feedback": (f"Wrong target: front document is {front_name!r}, expected "
                             f"{EXPECTED_NAME!r}. Open the target file, do not switch to "
                             f"a different document."),
                "subscores": _empty_subscores()}

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: front document match (15 pts) ----
    subscores["front_document_match"] = 15
    feedback.append(f"Front document is {EXPECTED_NAME} (+15)")

    # ---- C2: target file integrity (10 pts) ----
    if target_exists and target_unchanged:
        subscores["target_file_integrity"] = 10
        feedback.append(f"Target file intact on disk ({target_size} bytes, expected {EXPECTED_SIZE}) (+10)")
    elif target_exists and not target_unchanged:
        feedback.append(f"Target file on disk has unexpected size {target_size} != {EXPECTED_SIZE} (+0)")
    else:
        feedback.append("Target file missing from disk at end of task (+0)")

    # ---- C3: playback started (40 pts) ----
    if current_time >= PLAY_STARTED_THRESHOLD:
        subscores["playback_started"] = 40
        feedback.append(f"Playback started: current_time={current_time:.3f}s >= {PLAY_STARTED_THRESHOLD}s (+40)")
    else:
        feedback.append(f"Playback never started or barely advanced: current_time={current_time:.3f}s < {PLAY_STARTED_THRESHOLD}s (+0)")

    # ---- C4: meaningful playback (30 pts) ----
    if current_time >= MEANINGFUL_PLAY_THRESHOLD:
        subscores["meaningful_playback"] = 30
        feedback.append(f"Meaningful playback: current_time={current_time:.3f}s >= {MEANINGFUL_PLAY_THRESHOLD}s (+30)")
    else:
        feedback.append(f"Playback did not reach {MEANINGFUL_PLAY_THRESHOLD}s: current_time={current_time:.3f}s (+0)")

    # ---- C5: process alive (5 pts) ----
    if process_running:
        subscores["process_alive"] = 5
        feedback.append("QuickTime Player still running (+5)")
    else:
        feedback.append("QuickTime Player not running at task end (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD

    # Sanity: duration recorded should roughly match the expected duration; if
    # it diverges by more than 0.05s we surface it (does not affect score).
    if abs(duration - EXPECTED_DURATION) > 0.05:
        feedback.append(f"NOTE: front_document_duration={duration:.3f}s differs from "
                        f"expected {EXPECTED_DURATION:.3f}s — file may have been replaced.")

    if passed:
        feedback.insert(0, f"PASSED ({total}/100): agent advanced playback past {MEANINGFUL_PLAY_THRESHOLD}s.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): playback did not reach the pass threshold of {PASS_THRESHOLD} pts.")

    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
