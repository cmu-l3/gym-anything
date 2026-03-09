#!/usr/bin/env python3
"""
Verifier for rotate_oauth_credentials_workflow task.

Scoring Criteria:
1. Old App Deleted (20 pts)
2. New App Created (20 pts)
3. New App Config Matches Old Config (Redirect URIs, Client Type, Grant Type) (40 pts)
4. Credentials Saved Correctly (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rotate_oauth_credentials(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    expected_uris = metadata.get('expected_redirect_uris', '').strip()
    
    # Retrieve result file
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
    
    v1_exists = result.get("v1_exists", True)
    v2_exists = result.get("v2_exists", False)
    v2_config = result.get("v2_config", {})
    
    # 1. Old App Deleted (20 pts)
    if not v1_exists:
        score += 20
        feedback_parts.append("✓ Old application 'Logistics_Fleet_Sync_v1' successfully deleted.")
    else:
        feedback_parts.append("✗ Old application 'Logistics_Fleet_Sync_v1' still exists.")

    # 2. New App Created (20 pts)
    if v2_exists:
        score += 20
        feedback_parts.append("✓ New application 'Logistics_Fleet_Sync_v2' created.")
    else:
        feedback_parts.append("✗ New application 'Logistics_Fleet_Sync_v2' not found.")
        # Critical failure for subsequent checks
        return {
            "passed": False, 
            "score": score, 
            "feedback": "\n".join(feedback_parts)
        }

    # 3. Configuration Integrity (40 pts)
    # Redirect URIs (20 pts)
    actual_uris = v2_config.get("redirect_uris", "").strip()
    # Sort URIs for comparison to handle order differences
    expected_uri_set = set(expected_uris.split())
    actual_uri_set = set(actual_uris.split())
    
    if expected_uri_set == actual_uri_set:
        score += 20
        feedback_parts.append("✓ Redirect URIs match exactly.")
    else:
        feedback_parts.append(f"✗ Redirect URI mismatch.\n  Expected: {expected_uris}\n  Got: {actual_uris}")

    # Client Type (10 pts)
    if v2_config.get("client_type") == "confidential":
        score += 10
        feedback_parts.append("✓ Client Type is 'Confidential'.")
    else:
        feedback_parts.append(f"✗ Client Type mismatch: Got {v2_config.get('client_type')}")

    # Grant Type (10 pts)
    if v2_config.get("authorization_grant_type") == "authorization-code":
        score += 10
        feedback_parts.append("✓ Grant Type is 'Authorization code'.")
    else:
        feedback_parts.append(f"✗ Grant Type mismatch: Got {v2_config.get('authorization_grant_type')}")

    # 4. Credentials Saved (20 pts)
    file_exists = result.get("file_exists", False)
    file_parsed = result.get("file_parsed", {})
    
    if file_exists:
        saved_id = file_parsed.get("client_id", "").strip()
        saved_secret = file_parsed.get("client_secret", "").strip()
        
        real_id = v2_config.get("client_id", "")
        real_secret = v2_config.get("client_secret", "")
        
        if saved_id == real_id and len(saved_secret) > 0:
            # Note: We can strictly match secret if DB stores plain text, 
            # otherwise just check it matches what we grabbed or is non-empty.
            # Django OAuth Toolkit stores hashed secrets in newer versions, 
            # but usually stores plain in older or returns plain on creation. 
            # Here we check ID strict match.
            score += 20
            feedback_parts.append("✓ Credentials saved to JSON file correctly.")
        else:
            feedback_parts.append(f"✗ Saved credentials do not match the new app in database.\n  Saved ID: {saved_id}\n  Actual ID: {real_id}")
    else:
        feedback_parts.append("✗ Credentials file '/home/ga/Documents/new_credentials.json' not found.")

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }