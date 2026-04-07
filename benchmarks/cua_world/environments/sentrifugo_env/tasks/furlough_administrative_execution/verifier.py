#!/usr/bin/env python3
"""
Verifier for furlough_administrative_execution task.

Uses `copy_from_env` to retrieve JSON export of database state.
Scoring:
- Status "Furloughed - Unpaid" exists: 15 pts
- Employee 008 is Furloughed: 10 pts
- Employee 011 is Furloughed: 10 pts
- Employee 014 is Furloughed: 10 pts
- Employee 017 is Furloughed: 10 pts
- Annual Leave policy deactivated: 25 pts
- Announcement "Plant Operations Pause" exists: 20 pts
Total: 100 points, Pass Threshold: 75 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_furlough_execution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_status = metadata.get('expected_status', 'Furloughed - Unpaid')
    pass_threshold = metadata.get('pass_threshold', 75)
    scoring = metadata.get('scoring', {})
    
    # Defaults in case metadata is missing
    pts_status = scoring.get('status_created', 15)
    pts_emp = scoring.get('employee_reclassified', 10)
    pts_leave = scoring.get('leave_deactivated', 25)
    pts_ann = scoring.get('announcement_published', 20)

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/furlough_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # 1. Check Status Creation
    if result.get("status_created"):
        score += pts_status
        feedback_parts.append(f"Status '{expected_status}' created (+{pts_status})")
    else:
        feedback_parts.append(f"Status '{expected_status}' NOT created (0/{pts_status})")

    # 2. Check Employee Reclassification
    emp_statuses = result.get("employee_statuses", {})
    for empid in ["EMP008", "EMP011", "EMP014", "EMP017"]:
        status = emp_statuses.get(empid, "None")
        if status == expected_status:
            score += pts_emp
            feedback_parts.append(f"{empid} correctly reassigned (+{pts_emp})")
        else:
            feedback_parts.append(f"{empid} has wrong status: '{status}' (0/{pts_emp})")

    # 3. Check Leave Deactivation
    leave_flag = result.get("annual_leave_active_flag")
    if leave_flag == 0:
        score += pts_leave
        feedback_parts.append(f"Annual Leave correctly deactivated (+{pts_leave})")
    elif leave_flag == 1:
        feedback_parts.append(f"Annual Leave is still active (0/{pts_leave})")
    else:
        feedback_parts.append(f"Annual Leave policy not found or error (0/{pts_leave})")

    # 4. Check Announcement
    if result.get("announcement_published"):
        score += pts_ann
        feedback_parts.append(f"Announcement published (+{pts_ann})")
    else:
        feedback_parts.append(f"Announcement NOT published (0/{pts_ann})")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }