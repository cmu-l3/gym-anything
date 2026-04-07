#!/usr/bin/env python3
"""
Verifier for contractor_audit_and_isolation task.

Scoring Logic (100 Points Total, Pass Threshold = 78):
- 12 points: 'External Contractors' department is created.
- 44 points (11 points x 4 employees): Expired contractors (EMP031, EMP032, EMP034, EMP037) are correctly deactivated.
- 44 points (11 points x 4 employees): Active contractors (EMP033, EMP035, EMP036, EMP038) remain active and are moved to 'External Contractors'.

Anti-Gaming Checks:
- If a user was deleted entirely instead of deactivated, their `isactive` will be returned as null and will fail to get the 11 points (enforcing the "do not delete" requirement).
- Applying one action to everyone indiscriminately bounds the score to a max of 56 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_contractor_audit_and_isolation(traj, env_info, task_info):
    """
    Evaluates the results JSON against the expected department and employee logic.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    pass_threshold = metadata.get('pass_threshold', 78)
    expired_contractors = metadata.get('expired_contractors', ['EMP031', 'EMP032', 'EMP034', 'EMP037'])
    active_contractors = metadata.get('active_contractors', ['EMP033', 'EMP035', 'EMP036', 'EMP038'])

    # 1. Department Evaluation
    ext_dept_exists = result.get('external_dept_exists', False)
    ext_dept_id = result.get('external_dept_id')
    
    if ext_dept_exists and ext_dept_id is not None:
        score += 12
        feedback_parts.append("Department 'External Contractors' successfully created (+12 pts).")
    else:
        feedback_parts.append("Department 'External Contractors' missing (+0 pts).")

    # 2. Employee Evaluation
    employees = result.get('employees', {})

    # Evaluate Expired Contractors (should be deactivated, not deleted)
    for empid in expired_contractors:
        emp_data = employees.get(empid, {})
        is_active = emp_data.get('isactive')

        if is_active == 0:
            score += 11
            feedback_parts.append(f"{empid} correctly deactivated (+11 pts).")
        elif is_active == 1:
            feedback_parts.append(f"{empid} is still active, should be deactivated (+0 pts).")
        elif is_active is None:
            feedback_parts.append(f"{empid} was missing/deleted, should only be deactivated (+0 pts).")

    # Evaluate Active Contractors (should remain active AND be moved to new department)
    for empid in active_contractors:
        emp_data = employees.get(empid, {})
        is_active = emp_data.get('isactive')
        emp_dept_id = emp_data.get('department_id')

        if is_active == 1:
            if ext_dept_exists and str(emp_dept_id) == str(ext_dept_id):
                score += 11
                feedback_parts.append(f"{empid} active and assigned to 'External Contractors' (+11 pts).")
            elif ext_dept_exists and str(emp_dept_id) != str(ext_dept_id):
                feedback_parts.append(f"{empid} is active but assigned to the wrong department (+0 pts).")
            else:
                feedback_parts.append(f"{empid} is active but the target department does not exist (+0 pts).")
        elif is_active == 0:
            feedback_parts.append(f"{empid} was wrongly deactivated (+0 pts).")
        else:
            feedback_parts.append(f"{empid} missing/deleted (+0 pts).")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }