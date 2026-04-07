#!/usr/bin/env python3
"""
Verifier for Odoo HR task: Consolidate Departments and Archive.

Criteria:
1. Employee 'Robert Miller' moved to 'Research & Development' (40 pts)
2. Source department 'R&D USA' has 0 employees (30 pts)
3. Source department 'R&D USA' is archived (active=False) (30 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_departments(traj, env_info, task_info):
    """
    Verify the departmental consolidation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values from metadata
    metadata = task_info.get('metadata', {})
    target_dept_name = metadata.get('target_department', 'Research & Development')
    
    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Error check
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    # CRITERION 1: Employee Transfer (40 pts)
    # Check if Robert Miller is in the correct department
    emp_dept_id = result.get("target_employee_dept_id", 0)
    target_dept_id = result.get("target_dept_id", -1)
    emp_dept_name = result.get("target_employee_dept", "None")

    if emp_dept_id == target_dept_id and target_dept_id != 0:
        score += 40
        feedback_parts.append(f"Employee correctly moved to '{target_dept_name}'")
    else:
        feedback_parts.append(f"Employee is in '{emp_dept_name}', expected '{target_dept_name}'")

    # CRITERION 2: Source Department Empty (30 pts)
    # Check if R&D USA has 0 employees
    source_count = result.get("source_dept_employee_count", -1)
    
    if source_count == 0:
        score += 30
        feedback_parts.append("Source department 'R&D USA' is empty")
    elif source_count > 0:
        feedback_parts.append(f"Source department still has {source_count} employee(s)")
    else:
        feedback_parts.append("Could not determine source department employee count")

    # CRITERION 3: Department Archived (30 pts)
    # Check if R&D USA is inactive
    source_exists = result.get("source_dept_exists", False)
    source_active = result.get("source_dept_active", True)

    if source_exists:
        if not source_active:
            score += 30
            feedback_parts.append("Department 'R&D USA' is archived")
        else:
            feedback_parts.append("Department 'R&D USA' is still active")
    else:
        feedback_parts.append("Department 'R&D USA' not found (deleted instead of archived?)")

    # Final verdict
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }