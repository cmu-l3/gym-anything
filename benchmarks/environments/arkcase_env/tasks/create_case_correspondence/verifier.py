#!/usr/bin/env python3
"""
Verifier for create_case_correspondence task.

Verifies:
1. Correspondence entry was created in the specific case.
2. Subject matches "Official Response - Records Request Determination".
3. Body contains required snippets.
4. Timestamps confirm creation during task window.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_case_correspondence(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load results
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

    # Scoring
    score = 0
    feedback_parts = []
    
    case_id = result.get('case_id')
    if not case_id:
        return {"passed": False, "score": 0, "feedback": "Setup failed: Target case ID not found."}

    # 1. Correspondence Exists (40 pts)
    # Check if we found a new correspondence object created during the task
    corr_found = result.get('correspondence_found', False)
    final_count = result.get('final_count', 0)
    initial_count = result.get('initial_count', 0)
    
    if corr_found:
        score += 40
        feedback_parts.append("New correspondence entry found.")
    elif final_count > initial_count:
        # Fallback: Count increased but maybe didn't match specific query filters in export script
        score += 20
        feedback_parts.append(f"Correspondence count increased ({initial_count}->{final_count}), but details couldn't be verified.")
    else:
        feedback_parts.append("No new correspondence detected.")
        return {"passed": False, "score": 0, "feedback": "Failed: No correspondence created."}

    # 2. Subject Match (30 pts)
    if result.get('subject_match', False):
        score += 30
        feedback_parts.append("Subject line is correct.")
    else:
        feedback_parts.append("Subject line mismatch or missing.")

    # 3. Body Match (30 pts)
    if result.get('body_match', False):
        score += 30
        feedback_parts.append("Body content contains required text.")
    else:
        feedback_parts.append("Body content missing required keywords.")

    # Pass/Fail determination
    # Must have found the correspondence AND matched at least the subject OR body to pass
    passed = (score >= 70)  # Requires existence (40) + subject (30) OR body (30)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }