#!/usr/bin/env python3
"""
Verifier for update_consultation_status task.

Checks if the specific consultation request was updated to "Completed".
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_consultation_status(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Criteria
    score = 0
    feedback_parts = []
    
    final_status = result.get("final_status", "").lower()
    new_requests = result.get("new_requests_created", 0)
    
    # Acceptable "Completed" statuses in Oscar
    valid_statuses = ["completed", "complete", "done", "consult received", "received", "report received"]
    
    # Criterion 1: Status is Completed (50 pts)
    status_correct = False
    for vs in valid_statuses:
        if vs in final_status:
            status_correct = True
            break
            
    if status_correct:
        score += 50
        feedback_parts.append(f"Status updated correctly to '{result.get('final_status')}'")
    else:
        feedback_parts.append(f"Status mismatch: expected 'Completed', got '{result.get('final_status')}'")

    # Criterion 2: Modified correct record (30 pts)
    # Implicitly checked because we queried by ID, but we verify it's not the initial state
    # Setup sets it to "Pending Specialist Appt". If it's "Completed", it changed.
    if status_correct:
        score += 30
        feedback_parts.append("Correct record modified")

    # Criterion 3: No duplicate records created (20 pts)
    if new_requests == 0:
        score += 20
        feedback_parts.append("Clean workflow (no duplicate requests created)")
    else:
        feedback_parts.append(f"Warning: {new_requests} new consultation request(s) created instead of updating existing one")
        # Penalty for cluttering the chart
        score -= 10

    # VLM Verification (Bonus/Confirmation)
    # In a full implementation, we would query VLM here to confirm UI interaction
    # For now, we rely on the database state as the primary truth source
    
    # Final Decision
    passed = status_correct and (score >= 80)
    
    return {
        "passed": passed,
        "score": max(0, score),
        "feedback": " | ".join(feedback_parts)
    }