#!/usr/bin/env python3
"""
Verifier for create_work_log_type task.
Verifies that a specific Work Log Type was created in the ServiceDesk Plus database
with the correct attributes (Name, Description, Rate).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_work_log_type(traj, env_info, task_info):
    """
    Verify the creation of the 'On-Site Repair' work log type.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    target_name = metadata.get("target_name", "On-Site Repair")
    target_rate = float(metadata.get("target_rate", 150.0))
    desc_keywords = metadata.get("target_desc_keywords", ["physical", "repair", "maintenance", "client"])

    # Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Record Existence (40 pts)
    record_found = result.get("record_found", False)
    if record_found:
        score += 40
        feedback_parts.append(f"Work Log Type '{target_name}' created successfully.")
    else:
        feedback_parts.append(f"FAILED: Work Log Type '{target_name}' not found in database.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Verify Hourly Rate (30 pts)
    # Rate might come as string "150.0000" or similar from DB
    actual_rate_str = result.get("rate", "0")
    try:
        actual_rate = float(actual_rate_str)
        # Allow small float tolerance
        if abs(actual_rate - target_rate) < 0.1:
            score += 30
            feedback_parts.append(f"Hourly rate correct (${actual_rate}).")
        else:
            feedback_parts.append(f"Hourly rate incorrect. Expected ${target_rate}, got ${actual_rate}.")
    except ValueError:
        feedback_parts.append(f"Could not parse rate value: '{actual_rate_str}'.")

    # 3. Verify Description Content (20 pts)
    actual_desc = result.get("description", "").lower()
    keywords_found = [kw for kw in desc_keywords if kw.lower() in actual_desc]
    
    if len(keywords_found) >= 2:
        score += 20
        feedback_parts.append("Description contains required details.")
    elif len(keywords_found) > 0:
        score += 10
        feedback_parts.append("Description partially matches requirements.")
    else:
        feedback_parts.append("Description missing or does not contain key details.")

    # 4. Anti-gaming / Clean Execution (10 pts)
    # Check if a new record was actually added
    initial_count = int(result.get("initial_count", 0))
    final_count = int(result.get("final_count", 0))
    
    if final_count > initial_count:
        score += 10
    else:
        # If record found but count didn't increase, it might have overwritten or logic weirdness
        # We accept it if record_found is true, but deduct these bonus points
        feedback_parts.append("Count check warning (no net increase).")

    # Final Pass Determination
    passed = (score >= 70) and record_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }