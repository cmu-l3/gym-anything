#!/usr/bin/env python3
"""
Verifier for edit_case_metadata task.
Verifies that the agent correctly updated the Date Decided and Extra fields
for the Tinker v. Des Moines case.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_case_metadata(traj, env_info, task_info):
    """
    Verify the changes to the Tinker case metadata.
    
    Criteria:
    1. Tinker item exists in DB (10 pts)
    2. Date Decided changed from original '1969' (15 pts)
    3. Date Decided matches 'February 24, 1969' (25 pts)
    4. Extra field is populated (15 pts)
    5. Extra field contains 'Docket No. 21' (25 pts)
    6. Modified during task window (Anti-gaming) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for basic errors
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Task Error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Item Found (10 pts)
    if result.get("item_found"):
        score += 10
        feedback_parts.append("Tinker case found")
    else:
        return {"passed": False, "score": 0, "feedback": "Target case 'Tinker v. Des Moines' not found in library."}

    # 2. Date Decided Check (40 pts total)
    date_val = result.get("date_decided", "")
    if date_val and date_val != "1969":
        score += 15 # Changed from original
        
        # Check correctness (Allow small case/format variations)
        target_date = "february 24, 1969"
        if date_val.lower() == target_date:
            score += 25
            feedback_parts.append("Date Decided correct")
        elif "feb" in date_val.lower() and "24" in date_val and "1969" in date_val:
            score += 20 # Slight format mismatch but mostly right
            feedback_parts.append(f"Date Decided accepted with minor formatting ({date_val})")
        else:
            feedback_parts.append(f"Date Decided incorrect (expected '{target_date}', got '{date_val}')")
    else:
        feedback_parts.append("Date Decided field not updated")

    # 3. Extra Field Check (40 pts total)
    extra_val = result.get("extra_field", "")
    if extra_val:
        score += 15 # Field populated
        
        # Check correctness
        target_extra = "docket no. 21"
        if target_extra in extra_val.lower():
            score += 25
            feedback_parts.append("Extra field correct")
        else:
            feedback_parts.append(f"Extra field incorrect (expected containing '{target_extra}', got '{extra_val}')")
    else:
        feedback_parts.append("Extra field is empty")

    # 4. Anti-gaming (10 pts)
    if result.get("modified_during_task"):
        score += 10
    else:
        feedback_parts.append("Warning: Item not modified during task timeframe")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }