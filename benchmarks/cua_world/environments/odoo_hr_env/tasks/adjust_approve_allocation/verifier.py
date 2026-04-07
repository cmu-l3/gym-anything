#!/usr/bin/env python3
"""
Verifier for Odoo HR Task: Adjust and Approve Allocation
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_adjust_approve_allocation(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Adjusted the allocation days from 5.0 to 3.0
    2. Approved (validated) the allocation
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    target_days = metadata.get('target_days', 3.0)
    target_state = metadata.get('target_state', 'validate')
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check existence
    if not result.get("allocation_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The target allocation record was deleted or not found."
        }

    final_state = result.get("final_state")
    final_days = result.get("final_days")
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Adjustment (60 points)
    # Strict check: must be exactly 3.0. If they left it at 5.0, they get 0 here.
    if final_days == target_days:
        score += 60
        feedback_parts.append(f"Allocation correctly adjusted to {target_days} days.")
    else:
        feedback_parts.append(f"Incorrect allocation amount: found {final_days}, expected {target_days}.")
        if final_days == 5.0:
            feedback_parts.append("Agent failed to modify the requested amount (Rubber Stamping).")

    # Criterion 2: Approval (40 points)
    # State must be 'validate' (Approved)
    if final_state == target_state:
        score += 40
        feedback_parts.append("Allocation approved successfully.")
    elif final_state == 'validate1':
        # Second approval needed - acceptable if config requires double validation
        score += 35 
        feedback_parts.append("Allocation in second approval stage (acceptable).")
    elif final_state == 'refuse':
        score = 0 # Fail if refused
        feedback_parts.append("Allocation was Refused instead of Approved.")
    elif final_state == 'confirm':
        score = 0 # Fail if still pending
        feedback_parts.append("Allocation is still Pending (not approved).")
    else:
        feedback_parts.append(f"Allocation in unexpected state: {final_state}")

    # Anti-gaming check: Timestamp
    # Ensure the record was actually modified
    write_date_str = result.get("write_date") # Format "YYYY-MM-DD HH:MM:SS"
    task_start_ts = result.get("task_start_ts", 0)
    
    modified_during_task = False
    if write_date_str:
        try:
            # Odoo returns UTC times usually
            write_dt = datetime.strptime(write_date_str.split('.')[0], "%Y-%m-%d %H:%M:%S")
            write_ts = write_dt.timestamp()
            # Allow slight clock skew, check if write happened after start
            if write_ts >= task_start_ts - 5: 
                modified_during_task = True
        except Exception:
            # If date parsing fails, fall back to value check logic
            pass
            
    if not modified_during_task and final_days == 5.0 and final_state == 'confirm':
        return {"passed": False, "score": 0, "feedback": "No changes detected to the record (Do Nothing)."}

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }