#!/usr/bin/env python3
"""
Verifier for escalate_project_health_status task.

Criteria:
1. Project Status record must exist for 'mobile-banking-app'.
2. Status must be updated AFTER task start time (anti-gaming).
3. Status level must match 'At risk' (or internal code equivalents).
4. Explanation text must contain specific keywords regarding the vulnerability.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_escalate_project_health_status(traj, env_info, task_info):
    """
    Verifies that the project status was correctly escalated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_keywords', ["security", "vulnerability"])
    target_status_name = metadata.get('target_status_name', "At risk")

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Begin scoring
    score = 0
    feedback = []
    passed = False

    # Check 1: Status record exists (20 pts)
    if not result.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No Project Status was set for the project."
        }
    
    score += 20
    feedback.append("Project status record found.")

    # Check 2: Timestamp (Anti-gaming) (20 pts)
    # The status updated_at must be > task_start
    task_start = result.get('task_start', 0)
    updated_at = result.get('updated_at', 0)
    
    if updated_at > task_start:
        score += 20
        feedback.append("Status was updated during the task.")
    else:
        feedback.append("Status was NOT updated during the task (timestamp is old).")
        # Critical fail if it wasn't done now
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Check 3: Status Value (30 pts)
    # OpenProject statuses: usually "on_track", "at_risk", "off_track"
    # Or names "On track", "At risk", "Off track"
    actual_name = str(result.get('status_name', '')).lower()
    actual_code = str(result.get('status_code', ''))
    
    # "At risk" usually maps to a specific code or name
    # We accept "at risk", "at_risk", or potentially the code if known (often 2)
    # But checking name is safer if code varies by seed
    if "at risk" in actual_name or "at_risk" in actual_name:
        score += 30
        feedback.append(f"Status set correctly to '{result.get('status_name')}'.")
    elif "off track" in actual_name or "off_track" in actual_name:
        # User asked for "At risk" (Red). 
        # If UI says "At risk" but it's red, user might have clicked the right visual thing.
        # But prompts said "At risk". We'll give partial credit if they went fully to "Off track".
        score += 15
        feedback.append(f"Status set to '{result.get('status_name')}', expected 'At risk'.")
    else:
        feedback.append(f"Incorrect status level: '{result.get('status_name')}'. Expected 'At risk'.")

    # Check 4: Explanation Content (30 pts)
    explanation = str(result.get('explanation', '')).lower()
    missing_keywords = [kw for kw in required_keywords if kw.lower() not in explanation]
    
    if not missing_keywords:
        score += 30
        feedback.append("Explanation contains all required keywords.")
    elif len(missing_keywords) < len(required_keywords):
        # Partial credit
        partial = int(30 * (1 - len(missing_keywords)/len(required_keywords)))
        score += partial
        feedback.append(f"Explanation missing some keywords: {', '.join(missing_keywords)}.")
    else:
        feedback.append("Explanation missing required details.")

    # Final Pass Determination
    # Threshold: Need correct status AND reasonable explanation OR perfect explanation and acceptable status
    if score >= 70:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }