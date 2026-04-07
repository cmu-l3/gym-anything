#!/usr/bin/env python3
"""
Verifier for process_employee_promotion task.

Verifies:
1. Ernest Reed's employee record exists.
2. 7 specific fields match the expected values (partial credit).
3. The record was modified *during* the task (timestamp check).
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_employee_promotion(traj, env_info, task_info):
    """
    Verify the employee promotion updates.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {})
    scoring = metadata.get('scoring', {})
    
    # Defaults if metadata is missing
    exp_job_title = expected.get("job_title", "Senior Research Analyst")
    exp_dept = expected.get("department_name", "Research & Development")
    exp_job_pos = expected.get("job_position_name", "Experienced Developer")
    exp_manager = expected.get("manager_name", "Marc Demo")
    exp_coach = expected.get("coach_name", "Tina Williamson")
    exp_phone_digits = expected.get("work_phone_digits", "6505550199")
    exp_email = expected.get("work_email", "ernest.reed@yourcompany.example.com")

    # Copy result file from container
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

    # Basic checks
    if not result.get("employee_found"):
        return {"passed": False, "score": 0, "feedback": "Employee 'Ernest Reed' not found in database"}

    # Anti-gaming check: Timestamp
    if not result.get("timestamp_valid", False):
        write_ts = result.get("write_date_ts", 0)
        task_start = result.get("task_start", 0)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Anti-gaming check failed: Record was not modified during task (Write: {write_ts}, Start: {task_start})"
        }

    fields = result.get("fields", {})
    score = 0
    feedback_parts = []
    
    # 1. Job Title
    act_job_title = fields.get("job_title", "").strip()
    if act_job_title.lower() == exp_job_title.lower():
        score += scoring.get("job_title", 15)
        feedback_parts.append("Job Title: OK")
    else:
        feedback_parts.append(f"Job Title: Fail (got '{act_job_title}')")

    # 2. Department
    act_dept = fields.get("department_name", "").strip()
    # Loose match for department to handle potential Odoo formatting differences
    if exp_dept.lower() in act_dept.lower():
        score += scoring.get("department", 15)
        feedback_parts.append("Department: OK")
    else:
        feedback_parts.append(f"Department: Fail (got '{act_dept}')")

    # 3. Job Position
    act_job_pos = fields.get("job_position_name", "").strip()
    if exp_job_pos.lower() in act_job_pos.lower():
        score += scoring.get("job_position", 15)
        feedback_parts.append("Job Position: OK")
    else:
        feedback_parts.append(f"Job Position: Fail (got '{act_job_pos}')")

    # 4. Manager
    act_manager = fields.get("manager_name", "").strip()
    if exp_manager.lower() in act_manager.lower():
        score += scoring.get("manager", 15)
        feedback_parts.append("Manager: OK")
    else:
        feedback_parts.append(f"Manager: Fail (got '{act_manager}')")

    # 5. Coach
    act_coach = fields.get("coach_name", "").strip()
    if exp_coach.lower() in act_coach.lower():
        score += scoring.get("coach", 15)
        feedback_parts.append("Coach: OK")
    else:
        feedback_parts.append(f"Coach: Fail (got '{act_coach}')")

    # 6. Work Phone (normalize digits)
    act_phone = fields.get("work_phone", "")
    act_phone_digits = re.sub(r"\D", "", act_phone)
    if exp_phone_digits in act_phone_digits:
        score += scoring.get("work_phone", 10)
        feedback_parts.append("Phone: OK")
    else:
        feedback_parts.append(f"Phone: Fail (got '{act_phone}')")

    # 7. Work Email
    act_email = fields.get("work_email", "").strip()
    if act_email.lower() == exp_email.lower():
        score += scoring.get("work_email", 15)
        feedback_parts.append("Email: OK")
    else:
        feedback_parts.append(f"Email: Fail (got '{act_email}')")

    # Final scoring logic
    # Min score to pass is 60 (as per README logic, though we use flexible scoring here)
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }