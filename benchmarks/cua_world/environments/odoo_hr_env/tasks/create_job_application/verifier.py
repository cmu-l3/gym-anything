#!/usr/bin/env python3
"""
Verifier for create_job_application task.

Checks if the correct applicant record was created in Odoo.
Primary verification is done via Database/API query (exported to JSON).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_job_application(traj, env_info, task_info):
    """
    Verifies that the agent created the job application correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expectations from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get("expected_name", "Maria Chen")
    expected_email = metadata.get("expected_email", "maria.chen@techmail.com")
    expected_job = metadata.get("expected_job", "Experienced Developer")
    expected_dept = metadata.get("expected_dept", "Research & Development")
    expected_salary = metadata.get("expected_salary", 75000)
    salary_tolerance = metadata.get("salary_tolerance", 500)

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Check if record found (Essential)
    if not result.get("found", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No job application found for 'Maria Chen'. Ensure you saved the record."
        }
    
    # Base score for creating the record
    score += 20
    feedback_parts.append("Applicant record created (+20)")

    # Anti-gaming check (Essential)
    if result.get("is_new", False):
        score += 10
        feedback_parts.append("New record confirmed (+10)")
    else:
        feedback_parts.append("WARNING: Record ID is not new (pre-existing data used?)")

    fields = result.get("fields", {})

    # Check Email (15 pts)
    # normalize check
    actual_email = str(fields.get("email", "")).strip().lower()
    if actual_email == expected_email.lower():
        score += 15
        feedback_parts.append("Email correct (+15)")
    else:
        feedback_parts.append(f"Email mismatch: found '{actual_email}'")

    # Check Phone (10 pts)
    # lenient check for phone digits
    expected_digits = "".join(filter(str.isdigit, "555-0142"))
    actual_digits = "".join(filter(str.isdigit, str(fields.get("phone", ""))))
    if expected_digits in actual_digits:
        score += 10
        feedback_parts.append("Phone correct (+10)")
    else:
        feedback_parts.append(f"Phone mismatch: found '{fields.get('phone', '')}'")

    # Check Job Position (20 pts)
    # Check if "Experienced Developer" is in the string (handling potential ID prefixes/suffixes if raw data leaked, though export script handles it)
    if expected_job.lower() in str(fields.get("job", "")).lower():
        score += 20
        feedback_parts.append("Job Position correct (+20)")
    else:
        feedback_parts.append(f"Job Position mismatch: found '{fields.get('job', '')}'")

    # Check Department (10 pts)
    if expected_dept.lower() in str(fields.get("department", "")).lower():
        score += 10
        feedback_parts.append("Department correct (+10)")
    else:
        feedback_parts.append(f"Department mismatch: found '{fields.get('department', '')}'")

    # Check Salary (15 pts)
    try:
        actual_salary = float(fields.get("salary", 0))
        if abs(actual_salary - expected_salary) <= salary_tolerance:
            score += 15
            feedback_parts.append("Salary correct (+15)")
        else:
            feedback_parts.append(f"Salary mismatch: found {actual_salary}")
    except (ValueError, TypeError):
        feedback_parts.append("Salary value invalid")

    # Final Pass/Fail determination
    # Threshold 60, but MUST match job and department to be useful
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }