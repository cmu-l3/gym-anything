#!/usr/bin/env python3
"""
Verifier for configure_dual_leave_approval task.

Verification Logic:
1. Primary: Check Odoo database for "Training Time Off" record.
   - leave_validation_type must be 'both' (Dual Approval).
   - responsible_ids must include Mitchell Admin (ID 2).
2. Anti-Gaming:
   - Record's write_date must be after task start time.
   - Configuration must differ from the initial state (which was reset in setup).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_dual_leave_approval(traj, env_info, task_info):
    """
    Verifies that the "Training Time Off" leave type was correctly configured
    for dual approval with Mitchell Admin as the officer.
    """
    # 1. Retrieve result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Extract Data
    leave_type_found = result.get("leave_type_found", False)
    current_validation = result.get("current_validation_type")
    current_responsibles = result.get("current_responsible_ids", [])
    write_date_ts = result.get("write_date_timestamp", 0)
    task_start_ts = result.get("task_start", 0)
    target_admin_id = result.get("mitchell_admin_id", 2)

    # 3. Score Calculation
    score = 0
    feedback_parts = []

    # Criterion A: Leave Type Exists (10 pts)
    if leave_type_found:
        score += 10
        feedback_parts.append("Found 'Training Time Off' record.")
    else:
        return {"passed": False, "score": 0, "feedback": "Could not find 'Training Time Off' leave type in database."}

    # Criterion B: Validation Type is 'both' (35 pts)
    # 'both' = "By Employee's Approver and Time Off Officer"
    if current_validation == 'both':
        score += 35
        feedback_parts.append("Approval type correctly set to 'Dual Approval' (both).")
    else:
        feedback_parts.append(f"Incorrect approval type: expected 'both', found '{current_validation}'.")

    # Criterion C: Mitchell Admin assigned (30 pts)
    if target_admin_id in current_responsibles:
        score += 30
        feedback_parts.append("Mitchell Admin correctly assigned as Time Off Officer.")
    else:
        feedback_parts.append(f"Mitchell Admin (ID {target_admin_id}) not found in responsible officers: {current_responsibles}.")

    # Criterion D: Change Detection (15 pts)
    # Setup set it to 'manager', so if it's 'both', it changed.
    if current_validation != 'manager':
        score += 15
        feedback_parts.append("Configuration changed from initial state.")
    else:
        feedback_parts.append("Configuration matches initial state (no change detected).")

    # Criterion E: Timestamp Verification (10 pts)
    # Ensure the modification happened during the task
    if write_date_ts > task_start_ts:
        score += 10
        feedback_parts.append("Record modification verified by timestamp.")
    else:
        feedback_parts.append("Warning: Record timestamp predates task start (did you save?).")

    # 4. Final Determination
    # Pass threshold: 65 (Requires at least correct validation type + correct officer assignment)
    passed = score >= 65 and current_validation == 'both' and (target_admin_id in current_responsibles)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }