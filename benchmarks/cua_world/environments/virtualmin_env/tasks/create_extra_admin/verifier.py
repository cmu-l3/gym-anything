#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_extra_admin(traj, env_info, task_info):
    """
    Verifies that the extra administrator was created with correct credentials.
    
    Scoring Criteria:
    - Admin exists in Virtualmin (40 pts)
    - Username matches exactly (20 pts)
    - Description/Real Name matches (20 pts)
    - Password is correct (verified via auth check) (20 pts)
    """
    # 1. Setup access to file from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metadata & Result Data
    metadata = task_info.get('metadata', {})
    expected_desc = metadata.get('expected_description', 'DevOps Contractor - Carter')
    
    admin_exists = result.get('admin_exists', False)
    auth_success = result.get('auth_success', False)
    actual_desc = result.get('actual_description', '')
    pre_existed = result.get('pre_existed', False)
    miniserv_exists = result.get('miniserv_entry_exists', False)

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Anti-gaming check
    if pre_existed:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Verification Failed: Admin account existed before task started (Anti-gaming)."
        }

    # Check 1: Existence (40 pts)
    if admin_exists or miniserv_exists:
        score += 40
        feedback_parts.append("Admin account created successfully.")
    else:
        feedback_parts.append("Admin account NOT found.")

    # Check 2: Username (Implicit in existence check via `virtualmin list-admins --name devops_carter`)
    # If the command returned data, the username is correct.
    if admin_exists:
        score += 20
        feedback_parts.append("Username correct.")
    else:
        feedback_parts.append("Username could not be verified.")

    # Check 3: Description (20 pts)
    # Allow partial match
    if expected_desc.lower() in actual_desc.lower() or actual_desc.lower() in expected_desc.lower():
        score += 20
        feedback_parts.append(f"Description verified ('{actual_desc}').")
    elif len(actual_desc) > 0:
        score += 10
        feedback_parts.append(f"Description partial mismatch (Expected: '{expected_desc}', Found: '{actual_desc}').")
    else:
        feedback_parts.append("Description missing or incorrect.")

    # Check 4: Password / Authentication (20 pts)
    if auth_success:
        score += 20
        feedback_parts.append("Password verified (authentication successful).")
    else:
        feedback_parts.append("Password incorrect (authentication failed).")

    # 4. Final Assessment
    passed = (score >= 80) and admin_exists and auth_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }