#!/usr/bin/env python3
"""
Verifier for deactivate_and_label_user task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deactivate_and_label_user(traj, env_info, task_info):
    """
    Verify the agent deactivated the user and changed their title.
    
    Criteria:
    1. User login is blocked (Functional check) - 20 pts
    2. API reports user is inactive (State check) - 40 pts
    3. API reports user title is 'Former Auditor' - 25 pts
    4. User record still exists (not deleted) - 10 pts
    5. Screenshot exists - 5 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    feedback = []
    
    # 1. Login Blocked (20 pts)
    if result.get('login_blocked', False):
        score += 20
        feedback.append("User login successfully blocked")
    else:
        feedback.append("FAIL: Target user can still log in")

    # 2. API Active Status (40 pts)
    # The API 'active' field should be false. Python sends boolean from JSON as True/False
    is_active = result.get('api_active_status')
    if is_active is False:
        score += 40
        feedback.append("User status set to Inactive in system")
    elif is_active is True:
        feedback.append("FAIL: User status is still Active")
    else:
        # Fallback to LDAP check if API failed
        ldap_uac = result.get('ldap_uac', '')
        if '514' in str(ldap_uac): # 514 is Disabled Account in AD
            score += 40
            feedback.append("User status verified Disabled via LDAP")
        else:
            feedback.append("FAIL: User status could not be verified as Inactive")

    # 3. Job Title (25 pts)
    actual_title = result.get('api_job_title', '').strip()
    expected_title = "Former Auditor"
    
    if actual_title.lower() == expected_title.lower():
        score += 25
        feedback.append(f"Job title updated correctly to '{actual_title}'")
    else:
        feedback.append(f"FAIL: Job title is '{actual_title}', expected '{expected_title}'")

    # 4. User Exists (10 pts)
    if result.get('user_exists_in_api', False):
        score += 10
        feedback.append("User record preserved (not deleted)")
    else:
        feedback.append("FAIL: User record not found (may have been deleted)")

    # 5. Screenshot (5 pts)
    if result.get('screenshot_exists', False):
        score += 5
    
    # Pass check
    # Must have deactivated (points from login block OR api status) AND updated title
    deactivated = (result.get('login_blocked', False) or result.get('api_active_status') is False)
    title_correct = (actual_title.lower() == expected_title.lower())
    
    passed = deactivated and title_correct and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }