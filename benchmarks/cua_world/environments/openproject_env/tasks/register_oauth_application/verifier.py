#!/usr/bin/env python3
"""
Verifier for register_oauth_application task.

Checks:
1. Valid credentials file created.
2. OAuth application exists in OpenProject database.
3. Application metadata (Redirect URI) matches requirements.
4. Captured Client ID in file matches Database UID.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_oauth_application(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_uri = metadata.get('target_redirect_uri', 'https://jenkins.intranet.example.com/oauth/callback')
    expected_name = metadata.get('target_app_name', 'Jenkins CI Pipeline')

    # Load result from container
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
    feedback_parts = []
    
    # Extract data
    db_data = result.get('db_result', {})
    file_data = result.get('file_content', {})
    file_exists = result.get('file_exists', False)
    file_valid = result.get('file_valid_json', False)
    task_start = result.get('task_start', 0)

    # Criterion 1: Database Check - App Existence (30 pts)
    if db_data.get('found'):
        created_at = db_data.get('created_at', 0)
        # Verify it was created during this session (allow 10s buffer before start just in case of clock skew)
        if created_at >= (task_start - 10):
            score += 30
            feedback_parts.append("OAuth application created successfully.")
        else:
            feedback_parts.append("Found OAuth app, but it existed before task started.")
    else:
        feedback_parts.append("No OAuth application found with name 'Jenkins CI Pipeline'.")

    # Criterion 2: Database Check - Metadata (20 pts)
    if db_data.get('found'):
        actual_uri = db_data.get('redirect_uri', '').strip()
        if actual_uri == expected_uri:
            score += 20
            feedback_parts.append("Redirect URI is correct.")
        else:
            feedback_parts.append(f"Redirect URI incorrect. Expected: {expected_uri}, Got: {actual_uri}")

    # Criterion 3: File Existence & Format (10 pts)
    if file_exists and file_valid:
        score += 10
        feedback_parts.append("Credentials file created and is valid JSON.")
    elif file_exists:
        score += 5
        feedback_parts.append("Credentials file exists but is invalid JSON.")
    else:
        feedback_parts.append("Credentials file not found.")

    # Criterion 4: Cross-Reference Client ID (30 pts)
    db_uid = db_data.get('uid', '')
    file_client_id = str(file_data.get('client_id', '')).strip()

    if db_data.get('found') and file_valid and db_uid and file_client_id:
        if db_uid == file_client_id:
            score += 30
            feedback_parts.append("Captured Client ID matches database record.")
        else:
            feedback_parts.append(f"Client ID mismatch. DB: {db_uid[:8]}..., File: {file_client_id[:8]}...")
    elif not db_data.get('found'):
        pass # Already penalized
    else:
        feedback_parts.append("Could not verify Client ID match (missing data).")

    # Criterion 5: Secret Capture (10 pts)
    # We can't verify the secret against DB easily (it's hashed), but we check if the agent saved *something*
    file_secret = str(file_data.get('client_secret', '')).strip()
    if file_valid and len(file_secret) > 10:
        score += 10
        feedback_parts.append("Client Secret appears to be captured.")
    elif file_valid:
        feedback_parts.append("Client Secret is missing or too short.")

    # Final result
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }