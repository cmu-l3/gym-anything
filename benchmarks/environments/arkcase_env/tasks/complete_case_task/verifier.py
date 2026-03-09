#!/usr/bin/env python3
"""
Verifier for complete_case_task@1.

Checks if the agent successfully closed the assigned task in ArkCase.
Scoring:
- 40 pts: Task status is CLOSED (or COMPLETED)
- 30 pts: Task status is NOT 'ACTIVE' (partial credit if status changed but not fully closed)
- 30 pts: Completion date is present in the record
- Penalties: "Do nothing" (status matches initial ACTIVE state) scores 0.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_complete_case_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parse results
    final_status = result.get("final_status", "UNKNOWN").upper()
    completed_date = result.get("completed_date", "null")
    task_id = result.get("task_id", "")
    
    score = 0
    feedback_parts = []
    
    # Valid closed statuses in ArkCase usually include CLOSED, COMPLETED, RESOLVED
    CLOSED_STATUSES = ["CLOSED", "COMPLETED", "RESOLVED", "DONE"]

    # Criterion 1: Task ID was found and verified
    if not task_id:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Setup failed to create task or verification failed to find it."
        }

    # Criterion 2: Status is CLOSED (40 pts)
    if final_status in CLOSED_STATUSES:
        score += 40
        feedback_parts.append(f"Task status verified as {final_status}")
    # Criterion 2b: Status changed from ACTIVE but not closed (Partial 15 pts)
    elif final_status != "ACTIVE" and final_status != "UNKNOWN":
        score += 15
        feedback_parts.append(f"Task status changed to {final_status} (expected CLOSED)")
    else:
        feedback_parts.append(f"Task status remained {final_status}")

    # Criterion 3: Completion date exists (30 pts)
    # This confirms the system registered the completion event
    if completed_date and completed_date.lower() != "null":
        score += 30
        feedback_parts.append("Completion date recorded")
    else:
        feedback_parts.append("No completion date found")

    # Criterion 4: Status Changed (30 pts)
    # Explicit points for moving away from initial state (Anti-gaming)
    if final_status != "ACTIVE" and final_status != "UNKNOWN":
        score += 30
    
    # UI Verification (VLM) - Optional bonus if VLM is available
    # We rely primarily on API verification here as it's more robust for data states.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }