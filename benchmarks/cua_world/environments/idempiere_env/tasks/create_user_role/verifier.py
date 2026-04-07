#!/usr/bin/env python3
"""
Verifier for create_user_role task in iDempiere.
Verifies that the user "Emily Clark" was created with correct attributes
and assigned the "GardenWorld Admin" role.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_role(traj, env_info, task_info):
    """
    Verify the user creation and role assignment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ----------------------------------------------------------------
    # 1. Retrieve Result JSON
    # ----------------------------------------------------------------
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

    # ----------------------------------------------------------------
    # 2. Parse Data
    # ----------------------------------------------------------------
    task_start = result.get('task_start', 0)
    user_data = result.get('user_data')
    
    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 3. Score Criteria
    # ----------------------------------------------------------------
    
    # Criterion 1: User record exists (20 pts)
    if user_data:
        score += 20
        feedback_parts.append("User 'Emily Clark' exists")
        
        # Anti-gaming: Check creation time
        created_ts = user_data.get('created_ts', 0)
        if created_ts < task_start:
            feedback_parts.append("(Warning: User appears to pre-date task start)")
            # We don't deduct points here assuming setup_task cleared it, 
            # but it's a flag for unusual behavior.
    else:
        feedback_parts.append("User 'Emily Clark' NOT found")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Email correct (15 pts)
    # iDempiere stores email in the 'email' field.
    # Note: Case sensitivity usually doesn't matter for email, but we check exact or lower.
    actual_email = (user_data.get('email') or "").strip()
    expected_email = "emily.clark@gardenworld.com"
    
    if actual_email == expected_email:
        score += 15
        feedback_parts.append("Email correct")
    elif actual_email.lower() == expected_email.lower():
        score += 15
        feedback_parts.append("Email correct (case insensitive)")
    else:
        feedback_parts.append(f"Email mismatch (Found: '{actual_email}')")

    # Criterion 3: Login enabled (20 pts)
    # In iDempiere, this is controlled by 'IsLoginUser'='Y' AND having a password
    is_login_user = user_data.get('isloginuser', 'N') == 'Y'
    has_password = user_data.get('has_password', 'N') == 'Y'
    
    if is_login_user and has_password:
        score += 20
        feedback_parts.append("Login enabled")
    elif is_login_user:
        score += 10
        feedback_parts.append("Login flag set but no password detected")
    elif has_password:
        score += 10
        feedback_parts.append("Password set but Login flag not checked")
    else:
        feedback_parts.append("Login disabled (flag unchecked, no password)")

    # Criterion 4: User active (10 pts)
    if user_data.get('isactive') == 'Y':
        score += 10
        feedback_parts.append("User Active")
    else:
        feedback_parts.append("User Inactive")

    # Criterion 5 & 6: Role assigned and active (35 pts total)
    # The SQL query returned a count of active role assignments for 'GardenWorld Admin'
    role_count = user_data.get('role_assigned_count', 0)
    
    if role_count > 0:
        score += 35  # Covers both assignment (25) and active status (10) as query checked both
        feedback_parts.append("Role 'GardenWorld Admin' assigned")
    else:
        feedback_parts.append("Role 'GardenWorld Admin' NOT assigned")

    # ----------------------------------------------------------------
    # 4. Final Result
    # ----------------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }