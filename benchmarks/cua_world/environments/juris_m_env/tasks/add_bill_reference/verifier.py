#!/usr/bin/env python3
"""
Verifier for add_bill_reference task.
Verifies that the agent created a Bill item with specific legislative metadata.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_bill_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """
    Verify that a Bill item was created with correct metadata.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve result JSON
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
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
            "feedback": f"Could not retrieve task results. Did the task complete successfully? Error: {e}",
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Task Error: {result['error']}"}

    # 2. Score Calculation
    score = 0
    feedback = []
    metadata = result.get("metadata", {})
    creator = result.get("creator", {})
    
    # CRITERION 1: Bill Item Exists (20 pts)
    if result.get("bill_found", False):
        score += 20
        feedback.append("Bill item created successfully (+20)")
    else:
        return {
            "passed": False,
            "score": 0, 
            "feedback": "No new Bill item found in the library. Ensure you created a 'Bill' item type.",
            "details": result
        }

    # CRITERION 2: Title (15 pts)
    title = metadata.get("title", "").lower()
    if "john lewis" in title and "voting rights" in title:
        score += 15
        feedback.append("Title correct (+15)")
    elif "voting rights" in title:
        score += 8
        feedback.append("Title partially correct (missing full name) (+8)")
    else:
        feedback.append(f"Title incorrect. Got: '{metadata.get('title')}'")

    # CRITERION 3: Bill Number (15 pts)
    bill_num = metadata.get("bill_number", "").lower().replace(" ", "").replace(".", "")
    if "hr4" in bill_num:
        score += 15
        feedback.append("Bill Number correct (+15)")
    elif "4" in bill_num:
        score += 5
        feedback.append("Bill Number partially correct (+5)")
    else:
        feedback.append(f"Bill Number incorrect. Got: '{metadata.get('bill_number')}'")

    # CRITERION 4: Legislative Body (10 pts)
    body = metadata.get("legislative_body", "").lower()
    if "house" in body or "representative" in body:
        score += 10
        feedback.append("Legislative Body correct (+10)")
    else:
        feedback.append(f"Legislative Body incorrect. Got: '{metadata.get('legislative_body')}'")

    # CRITERION 5: Session (10 pts)
    session = metadata.get("session", "").lower()
    if "117" in session:
        score += 10
        feedback.append("Session correct (+10)")
    else:
        feedback.append(f"Session incorrect. Got: '{metadata.get('session')}'")

    # CRITERION 6: Date (10 pts)
    date = metadata.get("date", "")
    if "2021" in date:
        score += 10
        feedback.append("Date correct (+10)")
    else:
        feedback.append(f"Date incorrect. Got: '{date}'")

    # CRITERION 7: Sponsor/Creator (15 pts)
    last_name = creator.get("last_name", "").lower()
    if "jackson" in last_name or "lee" in last_name:
        score += 15
        feedback.append("Sponsor correct (+15)")
    else:
        feedback.append(f"Sponsor incorrect. Got: '{creator.get('first_name')} {creator.get('last_name')}'")

    # CRITERION 8: Abstract (5 pts)
    abstract = metadata.get("abstract", "").lower()
    if len(abstract) > 20:
        score += 5
        feedback.append("Abstract populated (+5)")
    else:
        feedback.append("Abstract missing or too short")

    # Final result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }