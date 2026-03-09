#!/usr/bin/env python3
"""
Verifier for add_treaty_reference task.

Verification Strategy:
1. Load result JSON exported from the container.
2. Verify item existence: A "Treaty" item with correct title must exist.
3. Verify Metadata:
   - Title: "Vienna Convention on the Law of Treaties"
   - Short Title: "VCLT"
   - Date: "1969-05-23"
   - Reporter: "United Nations Treaty Series" (or UNTS)
   - Volume: "1155"
   - Page: "331"
4. Anti-gaming: Ensure item was created during the task window.

Scoring:
- Item created & correct type: 30 pts
- Title correct: 20 pts
- Citation details (Vol/Page/Reporter): 30 pts
- Date & Short Title: 20 pts
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_treaty_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the treaty reference was correctly added to Jurism."""
    
    # 1. Retrieve result from container
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_treaty_reference_result.json", temp.name)
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
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {result['error']}"}

    # 2. Analyze Result
    score = 0
    feedback = []
    
    item_found = result.get("item_found", False)
    item_type = result.get("item_type", "").lower()
    fields = result.get("fields", {})
    created_during_task = result.get("created_during_task", False)

    # Criterion 1: Item Existence and Type (30 pts)
    if item_found:
        if item_type == "treaty":
            score += 30
            feedback.append("Correct item type 'Treaty' created (+30)")
        else:
            score += 10
            feedback.append(f"Item created but wrong type: '{item_type}' (Expected: Treaty) (+10)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No item found with title 'Vienna Convention...'. Did you save the item?",
            "details": result
        }

    # Criterion 2: Title (20 pts)
    # Flexible matching for title
    title = fields.get("title", "")
    if "Vienna Convention on the Law of Treaties" in title:
        score += 20
        feedback.append("Title is correct (+20)")
    else:
        feedback.append(f"Title mismatch: '{title}'")

    # Criterion 3: Citation Details (30 pts total)
    # Reporter/Publication (10 pts)
    pub = fields.get("publicationTitle", "") or fields.get("reporter", "")
    if "United Nations Treaty Series" in pub or "UNTS" in pub:
        score += 10
        feedback.append("Reporter/Publication correct (+10)")
    else:
        feedback.append(f"Reporter mismatch: '{pub}' (Expected: United Nations Treaty Series)")

    # Volume (10 pts)
    vol = str(fields.get("volume", "") or fields.get("reporterVolume", ""))
    if "1155" in vol:
        score += 10
        feedback.append("Volume correct (+10)")
    else:
        feedback.append(f"Volume mismatch: '{vol}' (Expected: 1155)")

    # Page (10 pts)
    page = str(fields.get("pages", "") or fields.get("firstPage", ""))
    if "331" in page:
        score += 10
        feedback.append("Page correct (+10)")
    else:
        feedback.append(f"Page mismatch: '{page}' (Expected: 331)")

    # Criterion 4: Date and Short Title (20 pts total)
    # Date (10 pts)
    date_val = fields.get("date", "")
    if "1969-05-23" in date_val or "May 23, 1969" in date_val:
        score += 10
        feedback.append("Date correct (+10)")
    else:
        feedback.append(f"Date mismatch: '{date_val}' (Expected: 1969-05-23)")

    # Short Title (10 pts)
    short_title = fields.get("shortTitle", "")
    if "VCLT" in short_title:
        score += 10
        feedback.append("Short title correct (+10)")
    else:
        feedback.append(f"Short title mismatch: '{short_title}' (Expected: VCLT)")

    # Anti-gaming check (Pass/Fail condition, doesn't add points but required for pass)
    if not created_during_task:
        feedback.append("WARNING: Item timestamp indicates it was not created during this task session.")
        # We might penalize or fail, but strict fail is safer for anti-gaming
        return {
            "passed": False,
            "score": score,
            "feedback": "Verification Failed: The item was not created during the task session. " + " | ".join(feedback),
            "details": result
        }

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }