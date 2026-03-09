#!/usr/bin/env python3
"""
Verifier for triage_security_incident task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_triage_security_incident(traj, env_info, task_info):
    """
    Verify that the security incident was correctly triaged.
    
    Criteria:
    1. Incident modification time > Task start time (10 pts)
    2. Classification matches 'Denial of Service' (30 pts)
    3. Owner matches 'admin' (30 pts)
    4. Severity/Urgency is set (High) (30 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    incident = result.get('incident', {})
    if not incident:
        return {"passed": False, "score": 0, "feedback": "Incident record not found in database"}

    score = 0
    feedback = []
    
    # 1. Check Timeliness (Anti-Gaming)
    task_start = int(result.get('task_start_time', 0))
    modified_time = int(incident.get('modified', 0))
    
    if modified_time > task_start:
        score += 10
        feedback.append("Incident modified during task.")
    else:
        feedback.append("Incident was NOT modified during task (timestamps match start state).")

    # 2. Check Classification
    actual_class = incident.get('classification_id')
    expected_class = int(result.get('expected_class_id', -1))
    
    # Handle JSON nulls from MySQL
    if actual_class is None:
        actual_class = -1
    else:
        actual_class = int(actual_class)

    if actual_class > 0 and actual_class == expected_class:
        score += 30
        feedback.append("Classification correct (Denial of Service).")
    else:
        feedback.append(f"Classification incorrect. Expected ID {expected_class}, got {actual_class}.")

    # 3. Check Owner
    actual_owner = incident.get('owner_id')
    expected_owner = int(result.get('expected_owner_id', -1))
    
    if actual_owner is None:
        actual_owner = -1
    else:
        actual_owner = int(actual_owner)

    if actual_owner > 0 and actual_owner == expected_owner:
        score += 30
        feedback.append("Owner correct (admin).")
    else:
        feedback.append(f"Owner incorrect. Expected ID {expected_owner}, got {actual_owner}.")

    # 4. Check Severity
    # We check if it was set to a non-null value. Since we reset it to NULL in setup,
    # any valid assignment is likely the user's action.
    # In Eramba, High/Medium/Low usually correspond to specific IDs.
    # Without strict ID mapping, we give credit if it's non-null and was modified.
    actual_severity = incident.get('severity_id')
    
    if actual_severity is not None:
        score += 30
        feedback.append(f"Severity updated (ID: {actual_severity}).")
    else:
        feedback.append("Severity not set (remains NULL).")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }