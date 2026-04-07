#!/usr/bin/env python3
"""
Verifier for update_user_properties task.
Checks if the Nuxeo user 'jsmith' has been updated with the correct
First Name, Email, Company, and Group membership.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_user_properties(traj, env_info, task_info):
    """
    Verify the user profile updates.
    """
    # 1. Setup and copy result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Check if user exists
    if not result.get('user_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "User 'jsmith' was not found in the system. The account may have been deleted."
        }

    # 3. Extract User Properties
    user_data = result.get('user_data', {})
    properties = user_data.get('properties', {})
    
    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_firstname = metadata.get('expected_firstname', 'Jonathan')
    expected_email = metadata.get('expected_email', 'jonathan.smith@newcorp-intl.com')
    expected_company = metadata.get('expected_company', 'NewCorp International')
    expected_groups = set(metadata.get('expected_groups', ['members', 'powerusers']))

    # 4. Score Calculation
    score = 0
    feedback_parts = []
    
    # Check First Name (25 pts)
    actual_firstname = properties.get('firstName', '')
    if actual_firstname == expected_firstname:
        score += 25
        feedback_parts.append(f"✓ First Name updated to '{actual_firstname}'")
    else:
        feedback_parts.append(f"✗ First Name incorrect: expected '{expected_firstname}', got '{actual_firstname}'")

    # Check Email (25 pts)
    actual_email = properties.get('email', '')
    if actual_email == expected_email:
        score += 25
        feedback_parts.append(f"✓ Email updated to '{actual_email}'")
    else:
        feedback_parts.append(f"✗ Email incorrect: expected '{expected_email}', got '{actual_email}'")

    # Check Company (25 pts)
    actual_company = properties.get('company', '')
    if actual_company == expected_company:
        score += 25
        feedback_parts.append(f"✓ Company updated to '{actual_company}'")
    else:
        feedback_parts.append(f"✗ Company incorrect: expected '{expected_company}', got '{actual_company}'")

    # Check Groups (25 pts)
    # The groups list in Nuxeo usually contains group names
    actual_groups = set(properties.get('groups', []))
    
    # Check for critical group: powerusers
    has_powerusers = 'powerusers' in actual_groups
    # Check for retained group: members
    has_members = 'members' in actual_groups
    
    if has_powerusers and has_members:
        score += 25
        feedback_parts.append(f"✓ Group membership correct (added 'powerusers', kept 'members')")
    elif has_powerusers and not has_members:
        score += 15
        feedback_parts.append(f"⚠ Added 'powerusers' but removed 'members' (Partial credit)")
    elif not has_powerusers:
        feedback_parts.append(f"✗ Failed to add user to 'powerusers' group. Current groups: {list(actual_groups)}")

    # 5. Anti-gaming / Sanity Check
    # Verify timestamps to ensure result isn't stale (though setup clears artifacts, this is good practice)
    task_start = float(result.get('task_start', 0))
    task_end = float(result.get('task_end', 0))
    if task_end <= task_start:
        feedback_parts.append("⚠ Warning: Task duration invalid (possible artifact issue)")

    # 6. Final Result
    passed = (score >= 100) # strict pass required for data entry tasks usually, or set threshold
    
    # Adjusted threshold as per design: 50 points needed to pass
    passed = (score >= 50)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }