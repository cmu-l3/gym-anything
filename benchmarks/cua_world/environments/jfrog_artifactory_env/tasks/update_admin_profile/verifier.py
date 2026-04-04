#!/usr/bin/env python3
"""
Verifier for update_admin_profile task.
Checks:
1. Admin email was updated to 'admin@example.com'.
2. Encrypted password file exists and matches the actual value from API.
3. File was created during the task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_admin_profile(traj, env_info, task_info):
    """
    Verify the admin profile update task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_email = metadata.get('target_email', 'admin@example.com')
    
    # Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Email Update (40 pts)
    api_email = result.get('api_email', '')
    if api_email == expected_email:
        score += 40
        feedback_parts.append(f"Admin email correctly updated to {api_email}")
    else:
        feedback_parts.append(f"Admin email incorrect. Expected: {expected_email}, Got: '{api_email}'")

    # 2. Check File Existence & Creation (10 pts)
    file_exists = result.get('file_exists', False)
    file_created_during = result.get('file_created_during_task', False)
    
    if file_exists and file_created_during:
        score += 10
        feedback_parts.append("Password file created during task")
    elif file_exists:
        score += 5
        feedback_parts.append("Password file exists but timestamp is old")
    else:
        feedback_parts.append("Password file not found")

    # 3. Check File Content (50 pts)
    # The file content must match the API's encrypted password
    file_content = result.get('file_content', '').strip()
    actual_encrypted = result.get('api_encrypted_password', '').strip()
    
    # Validation: Encrypted passwords in Artifactory look like {AES}... or {DESede}...
    # They should definitely NOT be the plaintext 'password'
    if not actual_encrypted:
        feedback_parts.append("Error: Could not retrieve ground truth encrypted password from API")
    elif file_content == actual_encrypted:
        score += 50
        feedback_parts.append("Encrypted password retrieved correctly")
    elif file_content == "password":
        feedback_parts.append("File contains plaintext password, expected encrypted token")
    else:
        # Check for partial match or common copy-paste errors
        if actual_encrypted in file_content:
            score += 40
            feedback_parts.append("Encrypted password found in file (with extra whitespace/content)")
        else:
            feedback_parts.append("File content does not match encrypted password")
            logger.info(f"Expected: {actual_encrypted}, Got: {file_content}")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }