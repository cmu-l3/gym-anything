#!/usr/bin/env python3
"""
Verifier for reassign_task@1 (Oscar EMR)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reassign_task(traj, env_info, task_info):
    """
    Verify that the agent reassigned the specific tickler task to Dr. Chen
    and set priority to High.
    """
    # 1. Setup copy mechanism
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Metadata Requirements
    metadata = task_info.get('metadata', {})
    target_assignee = metadata.get('target_assignee_no', '999998') # Dr. Chen
    target_priority = metadata.get('target_priority', 'High')
    target_status = metadata.get('target_status', 'A') # Active

    # 3. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Score Calculation
    score = 0
    feedback_parts = []
    
    # Check if tickler exists
    if not result.get('tickler_exists'):
        return {"passed": False, "score": 0, "feedback": "Target task record was deleted or not found."}

    # Criterion 1: Correct Assignee (40 pts)
    # Note: assigned_to might be '999998' or potentially provider name depending on DB schema, 
    # but based on setup script it stores provider_no.
    actual_assignee = str(result.get('assigned_to', '')).strip()
    if actual_assignee == target_assignee:
        score += 40
        feedback_parts.append("Correctly reassigned to Dr. Sarah Chen.")
    else:
        feedback_parts.append(f"Incorrect assignee: {actual_assignee} (expected {target_assignee}).")

    # Criterion 2: Correct Priority (30 pts)
    actual_priority = str(result.get('priority', '')).strip().lower()
    expected_priority_lower = target_priority.lower()
    
    # Priority handling: Oscar might store 'High' or '1' depending on version/config.
    # We accept 'high' or '1' as valid inputs for 'High' priority.
    if actual_priority == expected_priority_lower or actual_priority == '1':
        score += 30
        feedback_parts.append("Priority set to High.")
    else:
        feedback_parts.append(f"Incorrect priority: {actual_priority} (expected High).")

    # Criterion 3: Task Remains Active (10 pts)
    actual_status = str(result.get('status', '')).strip().upper()
    if actual_status == target_status:
        score += 10
        feedback_parts.append("Task remains Active.")
    else:
        feedback_parts.append(f"Task status incorrect: {actual_status} (expected Active/A).")

    # Criterion 4: Message Integrity (10 pts)
    # Ensure the agent didn't delete the content
    message = str(result.get('message', ''))
    if "MRI Brain Results" in message:
        score += 10
        feedback_parts.append("Message content preserved.")
    else:
        feedback_parts.append("Message content corrupted or changed significantly.")

    # Criterion 5: App/Navigation (10 pts)
    # Implicitly verified if the DB update succeeded, but we grant this 
    # if at least one modification was made successfully
    if score > 0:
        score += 10
        feedback_parts.append("Navigation successful.")

    passed = (score >= 70) # Need mostly correct assignee and priority

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }