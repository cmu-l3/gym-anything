#!/usr/bin/env python3
"""
Verifier for add_manual_case task.

Verification strategy:
1. Read exported JSON from VM via copy_from_env
2. Check that a case named "Roe v. Wade" exists in the library
3. Check that key metadata fields (court, date) are filled in

Scoring (100 points):
- Case item with "Roe v. Wade" exists: 50 pts
- Court field contains "Supreme Court": 20 pts
- Date field contains "1973": 20 pts
- Added during task (anti-gaming): 10 pts

Pass threshold: 50 points (case item exists)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_manual_case(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that Roe v. Wade was manually added as a case item."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_manual_case_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback = []

    roe_found = result.get("roe_found", False)
    created_during_task = result.get("created_during_task", False)
    roe = result.get("roe", {})
    court = roe.get("court", "")
    date = roe.get("date_decided", "")

    logger.info(f"roe_found={roe_found}, court={court!r}, date={date!r}")

    # Case exists
    if roe_found:
        score += 50
        feedback.append("Roe v. Wade case item found in library (+50)")
    else:
        feedback.append(
            "Roe v. Wade NOT found. Click the green + button in the toolbar, "
            "choose 'Case', and fill in the case name."
        )
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback), "details": result}

    # Court field correct
    if "supreme" in court.lower():
        score += 20
        feedback.append(f'Court "{court}" accepted (+20)')
    elif court:
        score += 10
        feedback.append(f'Court "{court}" filled in (+10, expected "United States Supreme Court")')
    else:
        feedback.append("Court field is empty (fill in 'United States Supreme Court')")

    # Date field correct
    if "1973" in date:
        score += 20
        feedback.append(f'Date "{date}" accepted (+20)')
    elif date:
        score += 10
        feedback.append(f'Date "{date}" filled in (+10, expected 1973)')
    else:
        feedback.append("Date field is empty (fill in 1973)")

    # Added during task (anti-gaming check)
    if created_during_task:
        score += 10
        feedback.append("Item was added during task execution (+10)")

    passed = score >= 50
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": result,
    }
