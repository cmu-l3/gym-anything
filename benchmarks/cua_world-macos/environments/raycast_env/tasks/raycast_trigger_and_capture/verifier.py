"""Verifier for raycast_env::raycast_trigger_and_capture.

The task description (see task.json) asks the agent to (a) invoke Raycast via
its extension-path URL scheme \u2014 specifically
`open 'raycast://extensions/raycast/clipboard-history/clipboard-history'` \u2014
then (b) capture a fresh screenshot via `/usr/sbin/screencapture` at
/Users/lume/Desktop/raycast_screenshot.png.

Only extension-path URLs (`raycast://extensions/<author>/<extension>/<command>`)
log to Raycast's activity SQLite WAL. Easter-egg / visible-only URLs like
`raycast://confetti` render UI but write nothing to disk and would silently
fail criterion C4 \u2014 see `specific_env_notes/raycast_macos/notes.md`
"URL-scheme behavior" section.

The export hook (export_result.sh) produces
/tmp/raycast_trigger_and_capture_result.json with file/xattr metadata for the
screenshot plus a size delta on Raycast's activity SQLite WAL (proxy for
"agent actually triggered Raycast").

Scoring (100 points, pass at 60):
- 15 pts  C1 (screenshot_exists)     Deliverable PNG present at target path.
- 15 pts  C2 (screenshot_fresh)      Screenshot mtime > task_start.
- 20 pts  C3 (screencapture_xattr)   PNG carries com.apple.metadata:kMDItemIsScreenCapture,
                                     proving it was made by /usr/sbin/screencapture
                                     and not by another tool / a moved file.
- 50 pts  C4 (raycast_was_triggered) Raycast activity WAL grew by \u2265 1024 bytes
                                     after task_start. Background ticks alone
                                     fall well under that threshold in probes;
                                     URL-scheme triggers produce a multi-KB spike.

Anti-gaming gates (run before scoring):
- Do-nothing: NOT screenshot_exists AND wal_delta < threshold \u2192 0.
- Wrong-target (screenshot but no Raycast): screenshot_exists AND wal_delta
  < threshold \u2192 0. (Agent captured a screenshot but never actually triggered
  Raycast \u2014 they could have screenshotted the empty desktop with
  Cmd+Shift+3 and bypassed the whole Raycast URL-scheme path.)

Partial-credit invariant (Anti-Pattern #4):
After the wrong-target gate, the only path to non-zero score requires C4 to
fire (Raycast actually triggered). The reachable score combinations are:
  - C4 only                          = 50  < 60 (no pass; agent triggered
                                                 Raycast but never saved a
                                                 screenshot)
  - C4 + C1                          = 65  (pass; file exists but not via
                                            screencapture and/or stale)
  - C4 + C1 + C2                     = 80  (pass; fresh + raycast)
  - C4 + C1 + C2 + C3                = 100 (full pass; happy path)
Max partial below pass (excluding combos with C4=0 which are gated):
  C4 alone = 50, which is strictly less than the 60 pass threshold. \u2713

Read pattern: copy_from_env(/tmp/raycast_trigger_and_capture_result.json,
local_tmp) \u2014 produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
WAL_GROWTH_THRESHOLD_BYTES = 1024
REMOTE_RESULT = "/tmp/raycast_trigger_and_capture_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "screenshot_exists": 0,
        "screenshot_fresh": 0,
        "screencapture_xattr": 0,
        "raycast_was_triggered": 0,
    }


def verify_raycast_trigger_and_capture(
    traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]
) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False,
                "feedback": "env_info missing copy_from_env",
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

    task_start = int(data.get("task_start", 0) or 0)
    screenshot_exists = bool(data.get("screenshot_exists", False))
    screenshot_mtime = int(data.get("screenshot_mtime", 0) or 0)
    screencap_xattr = bool(data.get("screenshot_is_screencapture", False))
    wal_delta = int(data.get("wal_size_delta_bytes", 0) or 0)
    raycast_triggered = wal_delta >= WAL_GROWTH_THRESHOLD_BYTES

    # ---- Gate 1: do-nothing ----
    if not screenshot_exists and not raycast_triggered:
        return {"score": 0, "passed": False,
                "feedback": (
                    "No evidence of task completion: no screenshot at "
                    f"{data.get('screenshot_path')} and Raycast activity WAL "
                    f"did not grow (delta={wal_delta}B, threshold="
                    f"{WAL_GROWTH_THRESHOLD_BYTES}B)."
                ),
                "subscores": _empty_subscores()}

    # ---- Gate 2: wrong-target (screenshot exists but Raycast was never triggered) ----
    if screenshot_exists and not raycast_triggered:
        return {"score": 0, "passed": False,
                "feedback": (
                    f"Wrong target: a screenshot exists at {data.get('screenshot_path')} "
                    f"but Raycast was never actually triggered (activity WAL grew "
                    f"only {wal_delta}B; threshold {WAL_GROWTH_THRESHOLD_BYTES}B). "
                    "The task requires invoking a Raycast URL scheme; "
                    "screenshotting alone does not satisfy it."
                ),
                "subscores": _empty_subscores()}

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: screenshot exists (15 pts) ----
    if screenshot_exists:
        subscores["screenshot_exists"] = 15
        feedback.append(
            f"Screenshot exists at {data.get('screenshot_path')} "
            f"({data.get('screenshot_size_bytes', 0)} bytes) (+15)"
        )
    else:
        feedback.append(
            f"Screenshot missing at {data.get('screenshot_path')} (+0)"
        )

    # ---- C2: screenshot fresh (15 pts) ----
    if screenshot_exists and screenshot_mtime > task_start:
        subscores["screenshot_fresh"] = 15
        feedback.append(
            f"Screenshot is fresh (mtime={screenshot_mtime} > "
            f"task_start={task_start}) (+15)"
        )
    elif screenshot_exists:
        feedback.append(
            f"Screenshot mtime ({screenshot_mtime}) is NOT after "
            f"task_start ({task_start}) (+0)"
        )
    else:
        feedback.append("Screenshot freshness: skipped (file missing) (+0)")

    # ---- C3: screencapture xattr (20 pts) ----
    if screenshot_exists and screencap_xattr:
        subscores["screencapture_xattr"] = 20
        feedback.append(
            "Screenshot carries kMDItemIsScreenCapture xattr \u2014 made by "
            "/usr/sbin/screencapture (+20)"
        )
    elif screenshot_exists:
        feedback.append(
            "Screenshot lacks kMDItemIsScreenCapture xattr \u2014 may have been "
            "created by a tool other than /usr/sbin/screencapture (+0)"
        )
    else:
        feedback.append("Xattr check: skipped (file missing) (+0)")

    # ---- C4: raycast was triggered (50 pts) ----
    if raycast_triggered:
        subscores["raycast_was_triggered"] = 50
        feedback.append(
            f"Raycast activity WAL grew by {wal_delta}B (\u2265 "
            f"{WAL_GROWTH_THRESHOLD_BYTES}B threshold) \u2014 URL-scheme "
            "trigger confirmed (+50)"
        )
    else:
        feedback.append(
            f"Raycast activity WAL grew only {wal_delta}B (threshold "
            f"{WAL_GROWTH_THRESHOLD_BYTES}B) \u2014 no URL-scheme trigger detected (+0)"
        )

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): Raycast triggered + screenshot captured.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed,
            "feedback": " | ".join(feedback), "subscores": subscores}
