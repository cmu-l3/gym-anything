#!/usr/bin/env python3
"""
Verifier for restore_voided_encounter task.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_openmrs_date(date_str):
    """
    Parse OpenMRS ISO-8601 like date string.
    Example: "2023-10-25T14:30:00.000+0000"
    """
    if not date_str or date_str == "null":
        return None
    # Python 3.7+ fromisoformat handles simple ISO, but +0000 might need adjustment if no colon
    # Simplest way for comparison: just use timestamp if possible, or string compare if format is strict
    try:
        # Remove the timezone offset for simpler naive comparison or handle properly
        # OpenMRS usually returns +0000.
        # Let's try flexible parsing
        return datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S.000%z")
    except ValueError:
        try:
            # Fallback for different formats
            return datetime.strptime(date_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
        except ValueError:
            return None

def verify_restore_voided_encounter(traj, env_info, task_info):
    """
    Verifies that the specific voided encounter was restored (un-voided).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy unavailable"}
    
    # 1. Load result JSON
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Setup error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Data extraction
    is_voided = result.get("is_voided")
    date_changed_str = result.get("date_changed")
    task_start_ts = result.get("task_start_timestamp", 0)
    
    # Criterion 1: Encounter is NOT voided (50 pts)
    # Note: JSON booleans are True/False in Python
    if is_voided is False:
        score += 50
        feedback_parts.append("Success: Encounter is active (un-voided).")
    elif is_voided is True:
        feedback_parts.append("Failure: Encounter is still voided.")
    else:
        feedback_parts.append("Failure: Could not determine encounter status.")

    # Criterion 2: Modification Timestamp (Anti-gaming) (30 pts)
    # The 'dateChanged' field in OpenMRS is updated when an encounter is modified (e.g. unvoided)
    valid_modification = False
    if date_changed_str:
        dt_changed = parse_openmrs_date(date_changed_str)
        if dt_changed:
            # Convert task_start to datetime with timezone awareness if possible, or compare timestamps
            ts_changed = dt_changed.timestamp()
            if ts_changed > task_start_ts:
                valid_modification = True
                score += 30
                feedback_parts.append("Verification: Encounter was modified during the task window.")
            else:
                feedback_parts.append(f"Verification: Modification time ({ts_changed}) is before task start ({task_start_ts}).")
        else:
             feedback_parts.append("Verification: Could not parse modification date.")
    else:
        # If dateChanged is null, it hasn't been modified since creation/voiding in setup?
        # Actually, if we just unvoided it, dateChanged SHOULD be set.
        feedback_parts.append("Verification: No modification date found (did you save changes?).")

    # Criterion 3: Trajectory/VLM check (Simulated here via score buffer or external) (20 pts)
    # We'll use a placeholder for now, or check app_running
    if result.get("app_running"):
        score += 10
        feedback_parts.append("Browser is running.")
    
    # We assign the remaining 10 points if the primary goal is achieved, 
    # assuming they navigated the UI to do it (since API access isn't available to the agent easily)
    if is_voided is False and valid_modification:
        score += 10

    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }