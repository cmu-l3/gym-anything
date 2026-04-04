#!/usr/bin/env python3
"""
Verifier for fix_allcaps_author_names task.

Checks if the authors for three specific books have been corrected
from ALL CAPS to Title Case in the Juris-M database.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_allcaps_author_names(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify author name corrections."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve the result JSON
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
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Error during verification export: {result['error']}"}

    score = 0
    feedback = []
    
    # Define expected values
    targets = {
        "holmes": {"expected_first": "Oliver Wendell", "expected_last": "Holmes"},
        "hobbes": {"expected_first": "Thomas", "expected_last": "Hobbes"},
        "montesquieu": {"expected_first": "Charles", "expected_last": "Montesquieu"}
    }

    # Verify each target
    for key, expected in targets.items():
        data = result.get(key)
        
        if not data or data == "not_found":
            feedback.append(f"Book for {expected['expected_last']} not found in library.")
            continue
            
        actual_first = data.get("firstName", "")
        actual_last = data.get("lastName", "")
        field_mode = data.get("fieldMode", -1)
        
        # Check Last Name
        if actual_last == expected["expected_last"]:
            score += 15
            feedback.append(f"{expected['expected_last']}: Last name correct.")
        elif actual_last.upper() == expected["expected_last"].upper():
            feedback.append(f"{expected['expected_last']}: Last name still uppercase ({actual_last}).")
        else:
            feedback.append(f"{expected['expected_last']}: Last name incorrect ({actual_last}).")

        # Check First Name
        if actual_first == expected["expected_first"]:
            score += 15
            feedback.append(f"{expected['expected_last']}: First name correct.")
        elif actual_first.upper() == expected["expected_first"].upper():
            feedback.append(f"{expected['expected_last']}: First name still uppercase ({actual_first}).")
        else:
            feedback.append(f"{expected['expected_last']}: First name incorrect ({actual_first}).")

        # Check Field Mode (should be 0 for two-field)
        # We give a small bonus if mode is correct, or deduct if they merged it into one field
        if field_mode == 0:
            score += 3.33  # Approx 10 points total for 3 items
        else:
            feedback.append(f"{expected['expected_last']}: Incorrect field mode (single field?).")

    # Round score to integer
    final_score = int(round(score))
    
    # Pass threshold: 90 points (allows for minor mode error but requires casing to be correct)
    passed = final_score >= 90

    if passed:
        feedback.insert(0, "All author names corrected successfully.")
    else:
        feedback.insert(0, "Some corrections are missing or incorrect.")

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback),
        "details": result
    }