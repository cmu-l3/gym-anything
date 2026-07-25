"""Verifier for the Preview rotate_image_clockwise task.

Scoring (100 points, pass at 70):
- 15 pts  C1 input_exists     The canonical image is still present at
                              ~/Documents/preview_rotation_input.png.
- 25 pts  C2 input_fresh      The file's mtime is strictly greater than
                              task_start (i.e., it was re-saved during the
                              agent trajectory, not left untouched).
- 40 pts  C3 dimensions_swapped
                              Post-action (width, height) equals the
                              pre-action (height, width) — the signature of a
                              90° (CW or CCW) rotation, since the source
                              image is recorded by setup as non-square.
- 20 pts  C4 valid_image      sips can still read the file as an image (it's
                              not been corrupted by a botched save).

Pass threshold 70 is strictly greater than the maximum partial-only score
(15 + 25 + 0 + 20 = 60, "agent saved without rotating") → Anti-Pattern #4
is satisfied. The only way to cross the threshold is to actually rotate.

Anti-gaming gates (return score=0 immediately):
- No-work gate: NOT input_fresh AND NOT dimensions_swapped. Catches
  do-nothing (file mtime predates task_start by setup design) and
  wrong-target (agent worked on a different file). Without this gate,
  do-nothing would score C1+C4 = 35, which is below the pass threshold but
  not zero.
- Setup-failure gate: initial_width == 0. setup_task.sh asserts a non-square
  source and emits a 0-default if it failed; in that case the export's
  dimensions_swapped flag is meaningless. Refuse to score.

Read pattern: copy_from_env(/tmp/rotate_image_clockwise_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70
REMOTE_RESULT = "/tmp/rotate_image_clockwise_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "input_exists": 0,
        "input_fresh": 0,
        "dimensions_swapped": 0,
        "valid_image": 0,
    }


def verify_rotate_image_clockwise(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    # Pull the export-script JSON onto the host.
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

    input_exists = bool(data.get("input_exists", False))
    input_fresh = bool(data.get("input_fresh", False))
    input_valid = bool(data.get("input_valid_image", False))
    dims_swapped = bool(data.get("dimensions_swapped", False))
    init_w = int(data.get("initial_width", 0) or 0)
    init_h = int(data.get("initial_height", 0) or 0)
    cur_w = int(data.get("current_width", 0) or 0)
    cur_h = int(data.get("current_height", 0) or 0)

    # ---- Setup-failure gate ----
    if init_w == 0 or init_h == 0:
        return {"score": 0, "passed": False,
                "feedback": ("Setup did not record valid initial dimensions "
                             "(initial_width or initial_height is 0). The rotation "
                             "check cannot run — investigate setup_task.sh."),
                "subscores": _empty_subscores()}

    # ---- No-work gate (catches do-nothing and wrong-target) ----
    if not input_fresh and not dims_swapped:
        return {"score": 0, "passed": False,
                "feedback": ("No evidence of task completion: the input file's mtime "
                             "is not greater than task_start AND its pixel dimensions "
                             f"are unchanged ({cur_w}x{cur_h}, same as initial {init_w}x{init_h})."),
                "subscores": _empty_subscores()}

    subscores = _empty_subscores()
    feedback: list[str] = []

    if input_exists:
        subscores["input_exists"] = 15
        feedback.append("Input file present at expected path (+15)")
    else:
        feedback.append("Input file missing at expected path (+0)")

    if input_fresh:
        subscores["input_fresh"] = 25
        feedback.append("File mtime is greater than task_start — re-saved during task (+25)")
    else:
        feedback.append("File mtime predates task_start — no save detected (+0)")

    if dims_swapped:
        subscores["dimensions_swapped"] = 40
        feedback.append(
            f"Dimensions swapped {init_w}x{init_h} → {cur_w}x{cur_h} — 90° rotation detected (+40)"
        )
    else:
        feedback.append(
            f"Dimensions unchanged ({init_w}x{init_h} → {cur_w}x{cur_h}) — rotation not detected (+0)"
        )

    if input_valid:
        subscores["valid_image"] = 20
        feedback.append("sips can still decode the file as an image (+20)")
    else:
        feedback.append("File is not a valid image per sips (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): image rotated and saved in place.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): rotation+save not detected (pass threshold {PASS_THRESHOLD}).")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
