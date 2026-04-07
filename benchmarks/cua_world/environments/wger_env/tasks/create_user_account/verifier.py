#!/usr/bin/env python3
"""
Verifier for create_user_account task.

Queries the database via exported task result file to ensure the account was 
created successfully, all expected fields are correctly populated, and
verifies the active status and password through a live API authentication test.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_account(traj, env_info, task_info):
    """
    Verify that the user account was correctly established.
    Uses copy_from_env to read pre-exported verification data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Extract exported details securely
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    user_exists = result.get("user_exists", False)
    first_name = result.get("first_name", "")
    last_name = result.get("last_name", "")
    email = result.get("email", "")
    is_active = result.get("is_active", "f")
    token_obtained = result.get("token_obtained", False)
    
    if user_exists:
        score += 25
        feedback.append("User 'maria_santos' exists (+25)")
        
        # Check First Name
        if first_name == "Maria":
            score += 15
            feedback.append("First name is correct (+15)")
        else:
            feedback.append(f"First name incorrect (expected 'Maria', got '{first_name}')")
            
        # Check Last Name
        if last_name == "Santos":
            score += 15
            feedback.append("Last name is correct (+15)")
        else:
            feedback.append(f"Last name incorrect (expected 'Santos', got '{last_name}')")
            
        # Check Email
        if email == "maria.santos@fitnessgym.com":
            score += 15
            feedback.append("Email is correct (+15)")
        else:
            feedback.append(f"Email incorrect (expected 'maria.santos@fitnessgym.com', got '{email}')")
            
        # Check Active State (Postgres handles bools as 't', 'true', etc.)
        if str(is_active).lower() in ["t", "true", "1"]:
            score += 10
            feedback.append("User is active (+10)")
        else:
            feedback.append("User is NOT active")
            
        # Check Password Validity (From JWT token response in export_result.sh)
        if token_obtained:
            score += 20
            feedback.append("Password is correct and works via API (+20)")
        else:
            feedback.append("Could not authenticate with provided password (did you set it correctly?)")
            
        # Anti-gaming: Ensure user was not pre-existing
        date_joined = result.get("date_joined", 0)
        task_start = result.get("task_start", 0)
        
        # Adding a 60-second buffer because clock desyncs can occasionally occur between host/docker
        if task_start > 0 and date_joined > 0 and date_joined < (task_start - 60):
            feedback.append("WARNING: User appears to have been created BEFORE the task started. Zeroing score.")
            score = 0
            
    else:
        feedback.append("User 'maria_santos' was NOT found in the database. Did you save the user?")
        
    # The agent passes if they score at least 70, but we mandate that the user MUST exist and be accessible via API
    passed = score >= 70 and user_exists and token_obtained
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }