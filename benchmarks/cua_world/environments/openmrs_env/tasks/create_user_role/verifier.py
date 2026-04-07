#!/usr/bin/env python3
"""
Verifier for Create User Role task.
Verifies that the 'Safety Auditor' role was created with specific privileges.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_user_role(traj, env_info, task_info):
    """
    Verify the agent created the Safety Auditor role correctly.
    
    Criteria:
    1. Role 'Safety Auditor' exists (40 pts)
    2. Description contains 'safety audits' (10 pts)
    3. Exactly 2 privileges assigned (20 pts)
    4. Privileges are exactly 'View Patients' and 'View Encounters' (20 pts)
    5. No inherited roles (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_role = metadata.get('expected_role', 'Safety Auditor')
    expected_privileges = set(metadata.get('expected_privileges', ["View Patients", "View Encounters"]))
    
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
    
    # 1. Check Role Existence (40 pts)
    role_exists = result.get('role_exists', False)
    role_name = result.get('role_name', '')
    
    if role_exists and role_name == expected_role:
        score += 40
        feedback_parts.append(f"Role '{expected_role}' created successfully")
    else:
        feedback_parts.append(f"Role '{expected_role}' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check Description (10 pts)
    description = result.get('role_description', '')
    if "safety audits" in description.lower():
        score += 10
        feedback_parts.append("Description correct")
    else:
        feedback_parts.append(f"Description missing key phrase 'safety audits' (Found: '{description}')")

    # 3. Check Privileges (40 pts total split)
    actual_privileges = set(result.get('privileges', []))
    
    # Check count
    if len(actual_privileges) == 2:
        score += 20
        feedback_parts.append("Correct number of privileges (2)")
    else:
        feedback_parts.append(f"Incorrect number of privileges: {len(actual_privileges)} (Expected 2)")

    # Check content
    missing = expected_privileges - actual_privileges
    extra = actual_privileges - expected_privileges
    
    if not missing and not extra:
        score += 20
        feedback_parts.append("Privileges match exactly")
    else:
        if missing:
            feedback_parts.append(f"Missing privileges: {list(missing)}")
        if extra:
            feedback_parts.append(f"Extra privileges: {list(extra)}")

    # 4. Check Inherited Roles (10 pts)
    # We want 0 inherited roles
    inherited_count = int(result.get('inherited_roles_count', 0))
    if inherited_count == 0:
        score += 10
        feedback_parts.append("No inherited roles (Correct)")
    else:
        feedback_parts.append(f"Role has {inherited_count} inherited roles (Expected 0)")

    # Final Pass Check
    # Must have created role and at least attempted privileges to pass
    passed = (score >= 80)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }