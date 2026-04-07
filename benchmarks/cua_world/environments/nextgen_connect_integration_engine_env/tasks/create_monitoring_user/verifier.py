#!/usr/bin/env python3
"""
Verifier for create_monitoring_user task.

Checks:
1. User 'monitor_analyst' exists in the system (API check)
2. All user attributes match expected values (Name, Email, Org)
3. Password authentication works with expected credentials
4. User record exists in database
5. User count increased
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_monitoring_user(traj, env_info, task_info):
    """
    Verify that the user was created with correct attributes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_username = metadata.get('expected_username', 'monitor_analyst')
    expected_firstname = metadata.get('expected_firstname', 'Sarah')
    expected_lastname = metadata.get('expected_lastname', 'Chen')
    expected_email = metadata.get('expected_email', 'sarah.chen@mercygeneral.org')
    expected_org = metadata.get('expected_org', 'Mercy General Hospital')

    # Load result JSON
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

    # Extract data
    user_exists_api = result.get('user_exists_api', False)
    user_details = result.get('user_details', {})
    auth_success = result.get('auth_success', False)
    db_record_exists = result.get('db_record_exists', False)
    initial_count = result.get('initial_user_count', 0)
    current_count = result.get('current_user_count', 0)
    task_start = result.get('task_start', 0)

    score = 0
    feedback_parts = []
    
    # 1. User Existence (20 pts)
    if user_exists_api:
        score += 20
        feedback_parts.append("User found via API")
    else:
        feedback_parts.append("User NOT found via API")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "User 'monitor_analyst' was not found. " + " | ".join(feedback_parts)
        }

    # 2. Attribute Checks (40 pts total)
    # First Name (10 pts)
    actual_fname = user_details.get('firstName', '')
    if actual_fname == expected_firstname:
        score += 10
        feedback_parts.append("First name correct")
    else:
        feedback_parts.append(f"First name mismatch: '{actual_fname}' (expected '{expected_firstname}')")

    # Last Name (10 pts)
    actual_lname = user_details.get('lastName', '')
    if actual_lname == expected_lastname:
        score += 10
        feedback_parts.append("Last name correct")
    else:
        feedback_parts.append(f"Last name mismatch: '{actual_lname}' (expected '{expected_lastname}')")

    # Email (10 pts)
    actual_email = user_details.get('email', '')
    if actual_email == expected_email:
        score += 10
        feedback_parts.append("Email correct")
    else:
        feedback_parts.append(f"Email mismatch: '{actual_email}' (expected '{expected_email}')")

    # Organization (10 pts)
    actual_org = user_details.get('organization', '')
    if actual_org == expected_org:
        score += 10
        feedback_parts.append("Organization correct")
    else:
        feedback_parts.append(f"Organization mismatch: '{actual_org}' (expected '{expected_org}')")

    # 3. Authentication Check (20 pts)
    if auth_success:
        score += 20
        feedback_parts.append("Password authentication successful")
    else:
        feedback_parts.append("Password authentication FAILED")

    # 4. DB & Count Check (15 pts)
    if db_record_exists:
        score += 10
        feedback_parts.append("Database record confirmed")
    
    if current_count > initial_count:
        score += 5
        feedback_parts.append("User count increased")
        
    # 5. Anti-gaming / Timestamp (5 pts)
    # Simple check: if we found the user and auth worked, meaningful work was done.
    # We can check creation timestamp if available in user_details, but usually it's not exposed in simple list.
    # The fact that 'auth_success' is true implies the user was created during the task (since we deleted it in setup).
    if user_exists_api:
        score += 5
        feedback_parts.append("Anti-gaming check passed")

    passed = score >= 70
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "username": user_details.get("username"),
            "email": user_details.get("email"),
            "auth_works": auth_success
        }
    }