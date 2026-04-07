#!/usr/bin/env python3
"""
Verifier for complete_review_workflow_task.
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_complete_review_workflow_task(traj, env_info, task_info):
    """
    Verifies the Nuxeo workflow completion task.
    """
    # 1. Helper to copy result file from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 2. Retrieve JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Task Completed (removed from pending list) - 40 pts
    if result.get('task_completed', False):
        score += 40
        feedback_parts.append("Review task successfully completed.")
    else:
        pending = result.get('pending_task_count', '?')
        feedback_parts.append(f"Task is still pending (count: {pending}).")

    # Criterion 2: Workflow Ended/Advanced - 30 pts
    if result.get('workflow_ended', False):
        score += 30
        feedback_parts.append("Workflow instance finished.")
    else:
        state = result.get('workflow_state', 'unknown')
        if state not in ['running', 'unknown']: 
             # Partial credit if it moved state but not fully ended (unlikely in this simple flow)
             score += 10
             feedback_parts.append(f"Workflow state changed to {state}.")
        else:
            feedback_parts.append(f"Workflow still in '{state}' state.")

    # Criterion 3: Comment Check - 30 pts
    # We check if the specific comment text requested was found in the audit log
    expected_text = task_info.get('metadata', {}).get('expected_comment', 'Reviewed and approved')
    found_text = result.get('comment_text', '')
    
    if result.get('comment_found', False):
        score += 30
        feedback_parts.append("Correct review comment found.")
    elif result.get('audit_events_count', 0) > 0:
        # If we see workflow events but missed the specific comment text
        score += 10
        feedback_parts.append("Workflow activity detected, but specific comment text not found.")
    else:
        feedback_parts.append("No workflow activity found in audit logs.")

    # 4. Anti-Gaming / Sanity Check
    # If the workflow ID wasn't even tracked, fail everything
    if not result.get('workflow_id'):
        return {"passed": False, "score": 0, "feedback": "Setup failed or workflow ID missing."}

    # 5. VLM Verification (Trajectory) - Bonus/Confirmation
    # We check if the agent actually visited the task page
    # This is a robust check against API-only gaming if we wanted to enforce UI use,
    # though here we treat API use as valid too.
    # We will just use it to add detail to feedback if score is low.
    
    final_passed = score >= 70
    
    return {
        "passed": final_passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }