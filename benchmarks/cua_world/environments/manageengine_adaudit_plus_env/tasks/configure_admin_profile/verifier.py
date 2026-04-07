#!/usr/bin/env python3
"""
Verifier for configure_admin_profile task.
Checks if the admin password was changed and profile details updated.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_admin_profile(traj, env_info, task_info):
    """
    Verify configure_admin_profile task.
    
    Criteria:
    1. Login with new password succeeds (30 pts)
    2. Login with old password fails (10 pts)
    3. Display Name updated (20 pts)
    4. Email updated (20 pts)
    5. Phone updated (10 pts)
    6. VLM verification of screenshot (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # Check 1: New Password
    if result.get('new_password_works'):
        score += 30
        feedback.append("Success: New password is active.")
    else:
        feedback.append("Fail: Cannot log in with new password.")
        
    # Check 2: Old Password
    if result.get('old_password_fails'):
        score += 10
        feedback.append("Success: Old password disabled.")
    else:
        feedback.append("Fail: Old password still works.")
        
    # Check 3: Display Name
    if result.get('display_name_correct'):
        score += 20
        feedback.append("Success: Display name updated.")
    else:
        feedback.append("Fail: Display name incorrect.")
        
    # Check 4: Email
    if result.get('email_correct'):
        score += 20
        feedback.append("Success: Email updated.")
    else:
        feedback.append("Fail: Email incorrect.")
        
    # Check 5: Phone
    if result.get('phone_correct'):
        score += 10
        feedback.append("Success: Phone number updated.")
    else:
        feedback.append("Fail: Phone number incorrect.")

    # Check 6: Visual/Screenshot Check (Basic existence check here, relying on VLM for deeper check if implemented)
    if result.get('screenshot_exists'):
        score += 10
    
    passed = (score >= 60 and result.get('new_password_works'))
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }