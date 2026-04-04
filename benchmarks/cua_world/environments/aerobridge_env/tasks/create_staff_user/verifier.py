#!/usr/bin/env python3
"""
Verifier for create_staff_user task.
Verifies that the 'ops_coordinator' user was created with correct attributes,
specifically checking the 'staff' vs 'superuser' distinction.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_staff_user(traj, env_info, task_info):
    """
    Verify the creation of the staff user.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_staff_user_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve validation data: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Metadata & Result Data
    metadata = task_info.get('metadata', {})
    expected_fname = metadata.get('target_first_name', 'Maria')
    expected_lname = metadata.get('target_last_name', 'Rodriguez')
    expected_email = metadata.get('target_email', 'maria.rodriguez@skyviewaerial.io')
    
    user_found = result.get('user_found', False)
    user_data = result.get('user_data', {})
    password_valid = result.get('password_valid', False)
    
    score = 0
    feedback_parts = []
    
    # 3. Scoring Logic
    
    # Criterion 1: User Exists (20 pts)
    if user_found:
        score += 20
        feedback_parts.append("✓ User 'ops_coordinator' exists (+20)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "User 'ops_coordinator' was not found in the system."
        }

    # Criterion 2: Name Correct (15 pts)
    # Be lenient with case or spaces, but strict on content
    actual_fname = user_data.get('first_name', '').strip()
    actual_lname = user_data.get('last_name', '').strip()
    
    if actual_fname == expected_fname and actual_lname == expected_lname:
        score += 15
        feedback_parts.append(f"✓ Name matched '{expected_fname} {expected_lname}' (+15)")
    else:
        feedback_parts.append(f"✗ Name mismatch. Expected '{expected_fname} {expected_lname}', got '{actual_fname} {actual_lname}'")

    # Criterion 3: Email Correct (10 pts)
    actual_email = user_data.get('email', '').strip()
    if actual_email == expected_email:
        score += 10
        feedback_parts.append(f"✓ Email matched '{expected_email}' (+10)")
    else:
        feedback_parts.append(f"✗ Email mismatch. Expected '{expected_email}', got '{actual_email}'")

    # Criterion 4: Staff Status (20 pts)
    if user_data.get('is_staff'):
        score += 20
        feedback_parts.append("✓ Staff status Enabled (+20)")
    else:
        feedback_parts.append("✗ Staff status is Disabled (User cannot log in to admin)")

    # Criterion 5: Superuser Status (15 pts) - CRITICAL Security Check
    if not user_data.get('is_superuser'):
        score += 15
        feedback_parts.append("✓ Superuser status Disabled (Correctly scoped privileges) (+15)")
    else:
        feedback_parts.append("✗ SECURITY FAIL: Superuser status is Enabled! This user should have limited privileges.")

    # Criterion 6: Password Valid (15 pts)
    if password_valid:
        score += 15
        feedback_parts.append("✓ Password is valid (+15)")
    else:
        feedback_parts.append("✗ Password validation failed. The user cannot log in with the requested password.")

    # Criterion 7: Anti-Gaming / Timestamp (5 pts)
    # We check if the count increased or if the user was created after task start
    # Since we deleted the user in setup, existence implies creation, but let's check count/time for robustness
    count_before = result.get('count_before', 0)
    current_count = result.get('current_count', 0)
    
    if current_count > count_before:
        score += 5
        feedback_parts.append("✓ User count increased correctly (+5)")
    else:
        feedback_parts.append("! User count did not increase (User might have existed despite cleanup?)")

    # 4. Final Assessment
    # Pass Threshold: 70 points
    # Mandatory checks for passing: User Exists, Staff=True, Superuser=False
    critical_met = user_found and user_data.get('is_staff') and not user_data.get('is_superuser')
    passed = (score >= 70) and critical_met

    if not critical_met:
        feedback_parts.append("\nFAILED: One or more critical criteria missing (User exists, Staff=True, Superuser=False).")

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }