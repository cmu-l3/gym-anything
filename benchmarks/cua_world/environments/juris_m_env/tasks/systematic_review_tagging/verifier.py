#!/usr/bin/env python3
"""
Verifier for systematic_review_tagging task.

Scoring (100 points total, pass threshold = 60):
  1. 'Included Studies' with >=6/9 free-speech cases (25 pts, partial >=3 = 12 pts):  25 pts
  2. 'Excluded Studies' with >=3/5 excluded cases (15 pts, partial >=1 = 7 pts):       15 pts
  3. 'free-speech' tag on >=6 free-speech cases (20 pts, partial >=3 = 10 pts):        20 pts
  4. Inconsistent tags removed (<=2 items still have bad tags = 10 pts, <=4 = 5 pts):  10 pts
  5. Notes with >=40 words on >=4 included cases (30 pts, >=2 = 15 pts, >=1 = 7 pts): 30 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

FREE_SPEECH_CASES = [
    "Tinker v. Des Moines Independent Community School District",
    "New York Times Co. v. Sullivan",
    "Brandenburg v. Ohio",
    "Schenck v. United States",
    "Texas v. Johnson",
    "Chaplinsky v. New Hampshire",
    "R.A.V. v. City of St. Paul",
    "Morse v. Frederick",
    "Bethel School District No. 403 v. Fraser",
]
EXCLUDED_CASES = [
    "Marbury v. Madison",
    "Brown v. Board of Education",
    "Miranda v. Arizona",
    "Gideon v. Wainwright",
    "Palsgraf v. Long Island Railroad Co.",
]
CANONICAL_TAG = "free-speech"
INCONSISTENT_TAGS = {"First Amendment", "expression", "free speech", "hate speech"}

# Note: Jurism stores notes as HTML; 40 words in HTML is roughly 200–300 characters.
# We use a conservative threshold of 200 characters to account for HTML markup overhead.
NOTE_LENGTH_THRESHOLD = 200


def _normalize(s: str) -> str:
    """Normalize a case name for fuzzy comparison."""
    return s.lower().strip().replace(".", "").replace(",", "").replace("  ", " ")


def _fuzzy_match(expected: str, actual_list: List[str]) -> bool:
    """Return True if expected case name roughly matches any item in actual_list."""
    norm_exp = _normalize(expected)
    for actual in actual_list:
        norm_act = _normalize(actual)
        if norm_exp in norm_act or norm_act in norm_exp:
            return True
    return False


def verify_systematic_review_tagging(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify the systematic review tagging task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON from the environment
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/systematic_review_tagging_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found. Was the post_task hook run?",
            }
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback = []
    details = {}

    # ---- Criterion 1: 'Included Studies' with >=6 free-speech cases (25 pts) ----
    try:
        included_exists = result.get("included_collection_exists", False)
        included_items = result.get("included_items", [])
        included_matched = sum(
            1 for case in FREE_SPEECH_CASES if _fuzzy_match(case, included_items)
        )
        if not included_exists:
            feedback.append("'Included Studies' collection NOT found (0)")
        elif included_matched >= 6:
            score += 25
            feedback.append(
                f"'Included Studies' has {included_matched}/9 free-speech cases (>=6 required) (+25)"
            )
        elif included_matched >= 3:
            score += 12
            feedback.append(
                f"'Included Studies' has {included_matched}/9 free-speech cases (partial, >=3) (+12)"
            )
        else:
            feedback.append(
                f"'Included Studies' has only {included_matched}/9 free-speech cases — too few (0)"
            )
        details["included_matched"] = included_matched
        details["included_collection_exists"] = included_exists
    except Exception as e:
        logger.warning(f"Criterion 1 error: {e}")

    # ---- Criterion 2: 'Excluded Studies' with >=3 excluded cases (15 pts) ----
    try:
        excluded_exists = result.get("excluded_collection_exists", False)
        excluded_items = result.get("excluded_items", [])
        excluded_matched = sum(
            1 for case in EXCLUDED_CASES if _fuzzy_match(case, excluded_items)
        )
        if not excluded_exists:
            feedback.append("'Excluded Studies' collection NOT found (0)")
        elif excluded_matched >= 3:
            score += 15
            feedback.append(
                f"'Excluded Studies' has {excluded_matched}/5 excluded cases (>=3 required) (+15)"
            )
        elif excluded_matched >= 1:
            score += 7
            feedback.append(
                f"'Excluded Studies' has {excluded_matched}/5 excluded cases (partial, >=1) (+7)"
            )
        else:
            feedback.append(
                f"'Excluded Studies' has {excluded_matched}/5 excluded cases — none correct (0)"
            )
        details["excluded_matched"] = excluded_matched
        details["excluded_collection_exists"] = excluded_exists
    except Exception as e:
        logger.warning(f"Criterion 2 error: {e}")

    # ---- Criterion 3: 'free-speech' canonical tag on >=6 free-speech cases (20 pts) ----
    try:
        all_item_tags = result.get("all_item_tags", {})
        canonical_tagged = 0
        for case in FREE_SPEECH_CASES:
            # Find the matching item in all_item_tags using fuzzy match
            for item_name, tags in all_item_tags.items():
                if _fuzzy_match(case, [item_name]):
                    if CANONICAL_TAG in tags:
                        canonical_tagged += 1
                    break
        if canonical_tagged >= 6:
            score += 20
            feedback.append(
                f"Canonical 'free-speech' tag on {canonical_tagged}/9 free-speech cases (>=6 required) (+20)"
            )
        elif canonical_tagged >= 3:
            score += 10
            feedback.append(
                f"Canonical 'free-speech' tag on {canonical_tagged}/9 free-speech cases (partial, >=3) (+10)"
            )
        else:
            feedback.append(
                f"Canonical 'free-speech' tag on only {canonical_tagged}/9 free-speech cases — too few (0)"
            )
        details["canonical_tagged"] = canonical_tagged
    except Exception as e:
        logger.warning(f"Criterion 3 error: {e}")

    # ---- Criterion 4: Inconsistent tags removed from included items (10 pts) ----
    try:
        all_item_tags = result.get("all_item_tags", {})
        included_items = result.get("included_items", [])
        still_inconsistent = 0
        for item_name in included_items:
            for item_key, tags in all_item_tags.items():
                if _fuzzy_match(item_name, [item_key]):
                    if any(t in INCONSISTENT_TAGS for t in tags):
                        still_inconsistent += 1
                    break
        if not included_items:
            # No included items means criterion is not yet applicable
            feedback.append("No 'Included Studies' items — cannot check tag consistency (0)")
        elif still_inconsistent <= 2:
            score += 10
            feedback.append(
                f"Inconsistent tags: only {still_inconsistent} included items still have bad tags (<=2 required) (+10)"
            )
        elif still_inconsistent <= 4:
            score += 5
            feedback.append(
                f"Inconsistent tags: {still_inconsistent} included items still have bad tags (partial, <=4) (+5)"
            )
        else:
            feedback.append(
                f"Inconsistent tags: {still_inconsistent} included items still have bad tags — too many (0)"
            )
        details["still_inconsistent"] = still_inconsistent
    except Exception as e:
        logger.warning(f"Criterion 4 error: {e}")

    # ---- Criterion 5: Notes on included cases (30 pts) ----
    try:
        notes_on_included = result.get("notes_on_included", [])
        # Count notes that meet the length threshold (>=200 chars approximates >=40 words in HTML)
        qualifying_notes = [
            n for n in notes_on_included if n.get("note_length", 0) >= NOTE_LENGTH_THRESHOLD
        ]
        # Deduplicate by caseName (count unique cases with qualifying notes)
        noted_cases = set()
        for n in qualifying_notes:
            case_name = n.get("caseName", "")
            if case_name:
                noted_cases.add(case_name)
        qualifying_count = len(noted_cases)

        if qualifying_count >= 4:
            score += 30
            feedback.append(
                f"Notes with >=40 words on {qualifying_count} included cases (>=4 required) (+30)"
            )
        elif qualifying_count >= 2:
            score += 15
            feedback.append(
                f"Notes with >=40 words on {qualifying_count} included cases (partial, >=2) (+15)"
            )
        elif qualifying_count >= 1:
            score += 7
            feedback.append(
                f"Notes with >=40 words on {qualifying_count} included case (partial, >=1) (+7)"
            )
        else:
            feedback.append(
                f"No qualifying notes (>=40 words) found on included cases (0)"
            )
        details["qualifying_notes_count"] = qualifying_count
        details["all_notes"] = notes_on_included
    except Exception as e:
        logger.warning(f"Criterion 5 error: {e}")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": details,
    }
