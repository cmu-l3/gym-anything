"""Verifier for the pages_env::draft_q3_product_memo task.

The task description (see task.json) asks the agent to draft a 3-priority Q3
product memo in Apple Pages, type three specific phrases into the body, and
save it as /Users/lume/Documents/Q3 Product Strategy Memo.pages.

The export hook (export_result.sh) walks the live Pages app via AppleScript
plus a filesystem check + .pages-bundle string scan, then writes
/tmp/draft_q3_product_memo_result.json.

Scoring (100 points, pass at 60):
- 20 pts  Criterion 1  Document saved at /Users/lume/Documents/Q3 Product Strategy Memo.pages
                       with mtime > task_start. Binary; either present-and-fresh
                       or not. This is the foundational gate: if it fails AND the
                       agent saved some other .pages file, we classify as wrong-
                       target and zero everything out. Partial credit (10 pts)
                       awarded if the file exists but mtime predates task_start
                       (means the agent moved a pre-existing file, not really
                       work).
- 25 pts  Criterion 2  Body contains "AI-assisted onboarding" (case-insensitive).
                       Binary.
- 25 pts  Criterion 3  Body contains "2026-09-30". Binary; exact date string.
- 30 pts  Criterion 4  Body contains "NPS from 42 to 55" AND "P0 incident rate" AND
                       "30%" (treated as 2-part: the NPS half = 15 pts, the P0
                       half = 15 pts, both required for full 30).

Anti-gaming gates (run before scoring):
- Do-nothing: target missing AND total_pages_post_start == 0 \u2192 0.
- Wrong-target: target missing AND any other .pages file was saved after
                task_start \u2192 0 (agent saved a doc but with the wrong filename).
- Title-missing: target missing in any other scenario \u2192 0 (no foundation
                 to award content credit \u2014 content gates require the doc to
                 exist at the right path).

Partial-credit invariant (Anti-Pattern #4):
All credit beyond C1 requires C1 (file present + fresh) because the gates
zero out content credit otherwise. So the worst-case partial-not-passing
score is:
  C1 (full) + 1 of C2/C3 = 20 + 25 = 45  < 60 pass threshold.
  C1 (full) + C4-half (NPS) = 20 + 15 = 35  < 60.
  C1 (stale-fallback 10) + C2 + C3 + C4 = 10 + 25 + 25 + 30 = 90 \u2192 PASS
    (this is intentional: a stale-mtime file that has all the right content
    is realistically a real save, just with a clock-skew oddity).
Smallest passing combo without stale-fallback: C1 + C2 + C3 = 70 PASS.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/draft_q3_product_memo_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "doc_saved": 0,
        "phrase_ai": 0,
        "phrase_date": 0,
        "phrase_nps_and_p0": 0,
    }


def verify_draft_q3_product_memo(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
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

    target_exists = bool(data.get("target_exists", False))
    target_fresh = bool(data.get("target_fresh", False))
    total_post_start = int(data.get("total_pages_post_start", 0) or 0)
    other_pages = data.get("other_post_start_pages", []) or []
    if not isinstance(other_pages, list):
        other_pages = []

    phrase_ai = bool(data.get("phrase_ai", False))
    phrase_date = bool(data.get("phrase_date", False))
    phrase_nps = bool(data.get("phrase_nps", False))
    phrase_p0 = bool(data.get("phrase_p0", False))

    # ---- Gate 1: do-nothing ----
    # Target missing AND no .pages activity at all after task_start. Note we
    # check on target_exists (not target_fresh) here \u2014 a stale-mtime file
    # at the target path is treated under C1's partial-credit branch.
    if not target_exists and total_post_start == 0:
        return {"score": 0, "passed": False,
                "feedback": ("No evidence of task completion: target document "
                             "/Users/lume/Documents/Q3 Product Strategy Memo.pages "
                             "is missing and no .pages files were saved after task start."),
                "subscores": _empty_subscores()}

    # ---- Gate 2: wrong-target ----
    # Target missing but the agent saved one or more other .pages files. Per
    # Pattern #2 in 03_verification_patterns.md, this is a strict zero \u2014
    # the agent demonstrated intent to save but with the wrong filename, so
    # awarding even content credit would be unsafe.
    if not target_exists and other_pages:
        return {"score": 0, "passed": False,
                "feedback": (f"Wrong target: a .pages document was saved after task start "
                             f"but the expected file '/Users/lume/Documents/Q3 Product Strategy "
                             f"Memo.pages' is missing. Other files: {other_pages}."),
                "subscores": _empty_subscores()}

    # ---- Gate 3: target missing for some unexpected reason ----
    # Catch-all: target is missing but neither gate fired (shouldn't happen
    # given how export populates the fields, but be defensive). No content
    # credit without the file.
    if not target_exists:
        return {"score": 0, "passed": False,
                "feedback": ("Target document is missing. Without the saved file at "
                             "/Users/lume/Documents/Q3 Product Strategy Memo.pages, "
                             "no content credit is awarded."),
                "subscores": _empty_subscores()}

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: doc saved at target path (20 pts, 10 for stale) ----
    if target_fresh:
        subscores["doc_saved"] = 20
        feedback.append("Document saved at expected path with fresh mtime (+20)")
    else:
        subscores["doc_saved"] = 10
        feedback.append("Document exists at expected path but mtime predates task start "
                        "(possible pre-existing file; +10)")

    # ---- C2: 'AI-assisted onboarding' (25 pts) ----
    if phrase_ai:
        subscores["phrase_ai"] = 25
        feedback.append("Body contains 'AI-assisted onboarding' (+25)")
    else:
        feedback.append("Body missing 'AI-assisted onboarding' (+0)")

    # ---- C3: '2026-09-30' (25 pts) ----
    if phrase_date:
        subscores["phrase_date"] = 25
        feedback.append("Body contains date '2026-09-30' (+25)")
    else:
        feedback.append("Body missing date '2026-09-30' (+0)")

    # ---- C4: NPS + P0 combo (30 pts, 15+15 split) ----
    nps_half = 15 if phrase_nps else 0
    p0_half = 15 if phrase_p0 else 0
    subscores["phrase_nps_and_p0"] = nps_half + p0_half
    if nps_half and p0_half:
        feedback.append("Body contains 'NPS from 42 to 55' AND 'P0 incident rate'/'30%' (+30)")
    elif nps_half:
        feedback.append("Body contains 'NPS from 42 to 55' but missing 'P0 incident rate' + '30%' (+15)")
    elif p0_half:
        feedback.append("Body contains 'P0 incident rate' + '30%' but missing 'NPS from 42 to 55' (+15)")
    else:
        feedback.append("Body missing both 'NPS from 42 to 55' and 'P0 incident rate'/'30%' (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): Q3 product memo draft saved and content verified.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): pass threshold {PASS_THRESHOLD}.")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
