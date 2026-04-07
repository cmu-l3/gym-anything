#!/usr/bin/env python3
"""
Verifier for Hire Job Applicant task.
Verifies that the applicant was moved to 'Contract Signed' and converted to an employee.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hire_job_applicant(traj, env_info, task_info):
    """
    Verify the hiring workflow completion.
    
    Criteria:
    1. Applicant 'Sofia Martinez' is in 'Contract Signed' stage.
    2. Employee 'Sofia Martinez' exists.
    3. Applicant is linked to the Employee record.
    4. Employee job position matches 'Experienced Developer'.
    5. Employee creation timestamp is valid (after task start).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Applicant Stage (35 pts)
    stage_name = result.get("applicant_stage_name", "")
    is_hired_stage = result.get("applicant_is_hired_stage", False)
    
    if is_hired_stage or "Contract Signed" in str(stage_name):
        score += 35
        feedback_parts.append("Applicant is in 'Contract Signed' stage (+35)")
    elif stage_name:
        feedback_parts.append(f"Applicant is in wrong stage: '{stage_name}' (0)")
    else:
        feedback_parts.append("Applicant record not found (0)")

    # 2. Employee Created (35 pts)
    employee_found = result.get("employee_found", False)
    if employee_found:
        score += 35
        feedback_parts.append("Employee record created (+35)")
    else:
        feedback_parts.append("Employee record NOT created (0)")

    # 3. Linkage (15 pts)
    # The applicant form should have the "Employee" field set to the new employee
    applicant_linked_emp_id = result.get("applicant_linked_emp_id")
    if applicant_linked_emp_id and employee_found:
        score += 15
        feedback_parts.append("Applicant is correctly linked to new Employee (+15)")
    elif employee_found:
        feedback_parts.append("Applicant record is NOT linked to the new Employee (-15)")

    # 4. Job Position Check (10 pts)
    job_title = result.get("employee_job_title", "")
    if "Experienced Developer" in str(job_title):
        score += 10
        feedback_parts.append("Employee has correct Job Position (+10)")
    elif employee_found:
        feedback_parts.append(f"Employee has incorrect Job Position: '{job_title}' (0)")

    # 5. Anti-gaming / Timestamp Check (5 pts)
    # Check that employee was created AFTER task start
    # Odoo dates are typically "YYYY-MM-DD HH:MM:SS"
    create_date_str = result.get("employee_create_date")
    task_start_ts = result.get("task_start", 0)
    
    timestamp_valid = False
    if create_date_str:
        try:
            # Odoo usually returns UTC string, e.g., "2023-10-25 10:00:00"
            # Simple check: parse and compare timestamps
            # If string contains dots (microseconds), handle that
            if "." in create_date_str:
                create_dt = datetime.strptime(create_date_str.split(".")[0], "%Y-%m-%d %H:%M:%S")
            else:
                create_dt = datetime.strptime(create_date_str, "%Y-%m-%d %H:%M:%S")
            
            create_ts = create_dt.timestamp()
            
            # Allow small clock skew (e.g. 60s) just in case, but usually container time is synced
            if create_ts >= (task_start_ts - 60):
                timestamp_valid = True
        except Exception as e:
            logger.warning(f"Date parsing failed: {e}")
            pass

    if timestamp_valid:
        score += 5
        feedback_parts.append("Creation timestamp valid (+5)")
    elif employee_found:
        feedback_parts.append("Creation timestamp invalid or missing (0)")

    # Pass Threshold
    # Must have at least Hired Stage AND Employee Created (35+35=70)
    passed = (score >= 70) and is_hired_stage and employee_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }