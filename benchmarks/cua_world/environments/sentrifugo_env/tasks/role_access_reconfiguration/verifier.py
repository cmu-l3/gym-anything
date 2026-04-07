#!/usr/bin/env python3
"""
Verifier for role_access_reconfiguration task in Sentrifugo.

Uses copy_from_env to read pre-exported verification data from the container.
Checks whether the three specified roles were created and whether the four
target employees were correctly assigned to these roles.

Scoring:
- 12 points per correctly created role (max 36 points)
- 16 points per correct employee assignment (max 64 points)
Total: 100 points
Pass Threshold: 64 points
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_role_access_reconfiguration(traj, env_info, task_info):
    """Verify role creation and employee assignment."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_roles = metadata.get('roles_to_create', ["Team Lead", "Finance Clerk", "Program Coordinator"])
    expected_assignments = metadata.get('employee_assignments', {
        "EMP005": "Team Lead",
        "EMP009": "Finance Clerk",
        "EMP014": "Program Coordinator",
        "EMP017": "Team Lead"
    })
    
    scoring = metadata.get('scoring', {"role_creation": 12, "employee_assignment": 16})
    pass_threshold = metadata.get('pass_threshold', 64)

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Pull the exported results JSON from the container
        copy_from_env("/tmp/role_access_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read exported result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve task result data: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    roles_created_dict = result.get('roles_created', {})
    employee_roles_dict = result.get('employee_roles', {})

    # Evaluate Role Creation
    for role in expected_roles:
        if roles_created_dict.get(role, False):
            score += scoring["role_creation"]
            feedback_parts.append(f"Role '{role}' successfully created (+{scoring['role_creation']} pts)")
        else:
            feedback_parts.append(f"Role '{role}' not found (0 pts)")

    # Evaluate Employee Role Assignments
    for empid, expected_role in expected_assignments.items():
        actual_role = employee_roles_dict.get(empid, "Unknown")
        
        # Exact string match is required
        if actual_role == expected_role:
            score += scoring["employee_assignment"]
            feedback_parts.append(f"Employee {empid} correctly assigned to '{expected_role}' (+{scoring['employee_assignment']} pts)")
        else:
            feedback_parts.append(f"Employee {empid} assigned to '{actual_role}', expected '{expected_role}' (0 pts)")

    # Determine if agent passed
    passed = score >= pass_threshold
    
    # Append final score summary
    feedback_parts.append(f"Total Score: {score}/{100} (Threshold: {pass_threshold})")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }