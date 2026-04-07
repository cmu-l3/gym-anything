#!/usr/bin/env python3
"""
Verifier for secure_user_profile_config task.

Criteria:
1. Profile SECURE_DEV_PROFILE exists (10 pts)
2. Profile Limits Correct (30 pts total)
   - SESSIONS_PER_USER = 2 (5 pts)
   - IDLE_TIME = 15 (5 pts)
   - FAILED_LOGIN_ATTEMPTS = 3 (5 pts)
   - PASSWORD_LOCK_TIME = 1 (5 pts)
   - PASSWORD_LIFE_TIME = 90 (5 pts)
   - PASSWORD_VERIFY_FUNCTION = STRICT_PASS_VERIFY (5 pts)
3. Verification Function STRICT_PASS_VERIFY exists (15 pts)
4. Function Logic Checks (based on source code analysis) (30 pts total)
   - Checks length (10 pts)
   - Checks numeric content (10 pts)
   - Checks username inclusion (10 pts)
5. HR User Assignment (5 pts)
6. HR Account Status is LOCKED (10 pts)

Pass Threshold: 70 pts
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/security_config_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check for DB errors
    if result.get("db_error"):
        return {"passed": False, "score": 0, "feedback": f"Database error during verification: {result['db_error']}"}

    # 1. Profile Existence (10 pts)
    if result.get("profile_exists"):
        score += 10
        feedback_parts.append("Profile SECURE_DEV_PROFILE exists (+10)")
    else:
        feedback_parts.append("Profile SECURE_DEV_PROFILE NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Profile Limits (30 pts)
    limits = result.get("profile_limits", {})
    
    # Helper to check limit
    def check_limit(name, expected_val, points):
        actual = str(limits.get(name, "")).strip()
        if actual == str(expected_val):
            return points, f"{name} correct"
        return 0, f"{name} incorrect (expected {expected_val}, got {actual})"

    p, msg = check_limit("SESSIONS_PER_USER", "2", 5)
    score += p; feedback_parts.append(msg)
    
    p, msg = check_limit("IDLE_TIME", "15", 5)
    score += p; feedback_parts.append(msg)
    
    p, msg = check_limit("FAILED_LOGIN_ATTEMPTS", "3", 5)
    score += p; feedback_parts.append(msg)
    
    p, msg = check_limit("PASSWORD_LOCK_TIME", "1", 5)
    score += p; feedback_parts.append(msg)
    
    p, msg = check_limit("PASSWORD_LIFE_TIME", "90", 5)
    score += p; feedback_parts.append(msg)
    
    # Check verify function assignment specifically
    assigned_func = limits.get("PASSWORD_VERIFY_FUNCTION", "").strip()
    # Oracle might store it with schema prefix or not, usually just name if in same schema or public synonym
    if "STRICT_PASS_VERIFY" in assigned_func:
        score += 5
        feedback_parts.append("Verify function assigned correctly (+5)")
    else:
        feedback_parts.append(f"Verify function not assigned (got {assigned_func})")

    # 3. Function Existence (15 pts)
    if result.get("function_exists"):
        score += 15
        feedback_parts.append("Function STRICT_PASS_VERIFY exists (+15)")
    else:
        feedback_parts.append("Function STRICT_PASS_VERIFY NOT found")
    
    # 4. Function Logic Checks (30 pts)
    # We analyze the source code for key logic patterns
    source_code = result.get("function_source", "").lower()
    
    if len(source_code) > 0:
        # Length check (look for length < 8)
        if "length" in source_code and ("8" in source_code or "eight" in source_code):
            score += 10
            feedback_parts.append("Length check found (+10)")
        else:
            feedback_parts.append("Length check logic unclear")

        # Numeric check (look for loop or digit check)
        if ("digit" in source_code or "number" in source_code or "0123456789" in source_code or "is_digit" in source_code):
            score += 10
            feedback_parts.append("Numeric check found (+10)")
        else:
            feedback_parts.append("Numeric check logic unclear")

        # Username check (look for username or user comparison)
        if ("username" in source_code or "user" in source_code) and ("instr" in source_code or "=" in source_code):
            score += 10
            feedback_parts.append("Username check found (+10)")
        else:
            feedback_parts.append("Username check logic unclear")
    else:
        feedback_parts.append("Function source empty or inaccessible")

    # 5. HR User Assignment (5 pts)
    hr_profile = result.get("hr_profile_assignment", "")
    if hr_profile == "SECURE_DEV_PROFILE":
        score += 5
        feedback_parts.append("HR assigned to profile (+5)")
    else:
        feedback_parts.append(f"HR profile incorrect ({hr_profile})")

    # 6. HR Account Status (10 pts)
    hr_status = result.get("hr_account_status", "")
    if "LOCKED" in hr_status and "TIMED" not in hr_status: 
        # "LOCKED(TIMED)" implies locking due to failed logins usually shown as "LOCKED(TIMED)" in some versions or just LOCKED depending on how recent
        # Actually failed login lock usually shows "LOCKED(TIMED)" or just "LOCKED"
        # The prompt asks to lock it via failed logins. 
        # Standard LOCKED status is acceptable evidence of locking.
        score += 10
        feedback_parts.append("HR account is LOCKED (+10)")
    elif "LOCKED" in hr_status:
        score += 10
        feedback_parts.append("HR account is LOCKED (+10)")
    else:
        feedback_parts.append(f"HR account status: {hr_status} (Expected LOCKED)")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }