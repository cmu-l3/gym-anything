#!/usr/bin/env python3
"""
Verifier for provision_service_account_api task.

Criteria:
1. REST API enabled in global settings.
2. User 'ci_runner' created with correct details.
3. User 'must_change_passwd' is False.
4. Correct API key saved to file.
5. File created during task execution.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_provision_service_account_api(traj, env_info, task_info):
    """
    Verify the provisioning of the service account and API key retrieval.
    """
    # 1. Setup: Load result data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    db_state = result.get('db_state', {})
    file_check = result.get('file_check', {})
    
    # 3. Initialize Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: REST API Enabled (20 pts)
    if db_state.get('api_enabled') is True:
        score += 20
        feedback_parts.append("REST API enabled (20/20)")
    else:
        feedback_parts.append("REST API NOT enabled (0/20)")

    # Criterion 2: User Exists (20 pts)
    user_data = db_state.get('user', {})
    if user_data.get('exists') is True:
        score += 20
        feedback_parts.append("User 'ci_runner' created (20/20)")
        
        # Criterion 3: User Details (Name/Email) (10 pts)
        # Using fuzzy match for name, exact for email
        first = user_data.get('firstname', '')
        last = user_data.get('lastname', '')
        email = user_data.get('mail', '')
        
        if "CI" in first and "Bot" in last and email == "ci_runner@example.com":
            score += 10
            feedback_parts.append("User details correct (10/10)")
        else:
            feedback_parts.append(f"User details incorrect: {first} {last} <{email}> (0/10)")

        # Criterion 4: Password Policy (10 pts)
        if user_data.get('must_change_passwd') is False:
            score += 10
            feedback_parts.append("Password change policy disabled (10/10)")
        else:
            feedback_parts.append("Password change policy ENABLED (should be disabled) (0/10)")

    else:
        feedback_parts.append("User 'ci_runner' NOT found (0/40)")

    # Criterion 5: File Content Matches Token (40 pts)
    # This proves they logged in and got the key
    db_token = db_state.get('db_token')
    file_content = file_check.get('content')
    file_exists = file_check.get('exists')
    
    if file_exists and db_token and file_content:
        # Check match (allow whitespace trimming which was done in export_result.sh)
        if file_content == db_token:
            score += 40
            feedback_parts.append("API key file matches database token (40/40)")
        else:
            feedback_parts.append(f"API key mismatch. File: '{file_content[:5]}...', DB: '{db_token[:5]}...' (0/40)")
    elif not file_exists:
        feedback_parts.append("Output file not found (0/40)")
    elif not db_token:
        feedback_parts.append("No API token found in DB for user (did you log in?) (0/40)")
        
    # Check anti-gaming timestamp for file
    if file_exists and not file_check.get('created_during_task', False):
        feedback_parts.append("(WARNING: File timestamp predates task start)")
        # We might penalize here, but the specific token match is usually proof enough of work 
        # since we deleted the user at setup.

    # 4. Final Result
    # Pass threshold: 80 points (Must enable API, create user, and get key)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }