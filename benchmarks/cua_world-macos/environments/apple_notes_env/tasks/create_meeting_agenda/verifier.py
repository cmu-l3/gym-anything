"""Verifier for the apple_notes_env::create_meeting_agenda task.

The task description (see task.json) asks the agent to create one Apple Notes
note titled exactly 'Q3 Planning Kickoff', with three required content lines
in the body. The export hook (export_result.sh) walks the live Notes app via
AppleScript and produces /tmp/create_meeting_agenda_result.json.

Scoring (100 points, pass at 60):
- 20 pts  Criterion 1  A note with title exactly 'Q3 Planning Kickoff' exists.
                       Binary; either present or not. This is the foundational
                       gate \u2014 if it fails, the wrong-target / do-nothing
                       protections below fire and the verifier returns 0.
- 25 pts  Criterion 2  Body contains 'Hire 3 senior engineers'.
                       Binary; phrase presence.
- 25 pts  Criterion 3  Body contains 'Q3 OKR' AND ('$5M' or '5M revenue').
                       Binary; two-token plausibility check.
- 30 pts  Criterion 4  Body contains '2026-08-15'.
                       Binary; exact date string \u2014 the description gives the
                       date explicitly, so this isn't a discovery test.

Anti-gaming gates (run before scoring):
- Do-nothing: matching_count == 0 AND total_notes_post_start == 0 \u2192 0.
- Wrong-target: matching_count == 0 AND any other notes were created after
  task_start \u2192 0 (the agent wrote a note but with the wrong title).
- Title-missing: matching_count == 0 in any other scenario \u2192 0 (no foundation
  to award content credit to).

Partial-credit invariant (Anti-Pattern #4):
All four criteria are binary (no partial), so the max-partial-not-passing
combinations are:
  - C2+C3 = 50  (no title) \u2192 gate prevents this from being reachable
  - C1+C2 = 45, C1+C3 = 45, C1+C4 = 50 (all < 60 pass threshold)
The smallest passing combination is C1+C2+C3 = 70 \u2014 i.e., the agent must
produce the right title AND at least two correct content lines to pass.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/create_meeting_agenda_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "note_exists": 0,
        "line_hire": 0,
        "line_okr": 0,
        "line_launch": 0,
    }


def verify_create_meeting_agenda(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    # Pull the export-script JSON into a host-side temp file.
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

    matching_count = int(data.get("matching_count", 0) or 0)
    total_post_start = int(data.get("total_notes_post_start", 0) or 0)
    other_titles = data.get("other_post_start_titles", []) or []
    if not isinstance(other_titles, list):
        other_titles = []

    # ---- Gate 1: do-nothing ----
    if matching_count == 0 and total_post_start == 0:
        return {"score": 0, "passed": False,
                "feedback": "No evidence of task completion: target note 'Q3 Planning Kickoff' "
                            "does not exist and no notes were created after task start.",
                "subscores": _empty_subscores()}

    # ---- Gate 2: wrong-target ----
    if matching_count == 0 and other_titles:
        return {"score": 0, "passed": False,
                "feedback": (
                    f"Wrong target: a note was created after task start but its title does not match "
                    f"'Q3 Planning Kickoff'. Found titles: {other_titles}."
                ),
                "subscores": _empty_subscores()}

    # ---- Gate 3: title missing despite post-start activity that didn't surface a title ----
    if matching_count == 0:
        return {"score": 0, "passed": False,
                "feedback": "Target note 'Q3 Planning Kickoff' is missing. Without the right title, "
                            "no content credit is awarded.",
                "subscores": _empty_subscores()}

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: note exists with target title (20 pts) ----
    subscores["note_exists"] = 20
    feedback.append("Note titled 'Q3 Planning Kickoff' exists (+20)")
    if matching_count > 1:
        feedback.append(f"(note: {matching_count} notes share this title; verifier scored the first)")

    # ---- C2: hire-line (25 pts) ----
    line_hire = bool(data.get("line_hire", False))
    if line_hire:
        subscores["line_hire"] = 25
        feedback.append("Body contains 'Hire 3 senior engineers' (+25)")
    else:
        feedback.append("Body missing 'Hire 3 senior engineers' (+0)")

    # ---- C3: OKR line (25 pts) ----
    line_okr = bool(data.get("line_okr", False))
    if line_okr:
        subscores["line_okr"] = 25
        feedback.append("Body contains 'Q3 OKR' and '$5M' (or '5M revenue') (+25)")
    else:
        feedback.append("Body missing 'Q3 OKR' + '$5M'/'5M revenue' phrasing (+0)")

    # ---- C4: launch-date line (30 pts) ----
    line_launch = bool(data.get("line_launch", False))
    if line_launch:
        subscores["line_launch"] = 30
        feedback.append("Body contains '2026-08-15' (+30)")
    else:
        feedback.append("Body missing '2026-08-15' (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): meeting agenda note created correctly.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
