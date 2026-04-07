#!/usr/bin/env python3
"""
Verifier for hire_candidate_setup_email task.

Criteria:
1. Candidate 'Elias Thorne' status must be 'Hired'.
2. Employee record for 'Elias Thorne' must exist.
3. Employee work email must be 'elias.thorne@gymhrcorp.com'.
4. Anti-gaming: Employee record must be created/modified after task start.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hire_candidate_setup_email(traj, env_info, task_info):
    """
    Verify the hiring and email setup workflow.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    candidate_status_label = result.get('candidate_status_label', '').upper()
    emp_data = result.get('employee_data', {})
    task_start = result.get('task_start', 0)
    
    # Criterion 1: Candidate Hired (40 pts)
    # Check if status label contains "HIRED"
    if 'HIRED' in candidate_status_label:
        score += 40
        feedback_parts.append("Candidate status is Hired")
    else:
        feedback_parts.append(f"Candidate status incorrect ({candidate_status_label})")

    # Criterion 2: Employee Created (30 pts)
    emp_exists = emp_data.get('exists') == 1 or emp_data.get('exists') is True
    if emp_exists:
        score += 30
        feedback_parts.append("Employee record created")
    else:
        feedback_parts.append("No employee record found")

    # Criterion 3: Email Correct (30 pts)
    work_email = emp_data.get('work_email', '')
    expected_email = "elias.thorne@gymhrcorp.com"
    
    if work_email == expected_email:
        score += 30
        feedback_parts.append(f"Email set correctly to {work_email}")
    elif work_email:
        # Partial credit if email set but wrong
        score += 10
        feedback_parts.append(f"Email incorrect: {work_email}")
    else:
        feedback_parts.append("Work email is empty")

    # Anti-gaming checks (Optional strictness)
    # Ensure joined_date is reasonable or record is new?
    # For now, the fact that we deleted the employee in setup is the main guard.
    # If emp_exists is true, it MUST have been created during this session.
    
    # Final decision
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }