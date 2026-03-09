#!/usr/bin/env python3
"""
Verifier for configure_legacy_service_connection task.

Criteria:
1. Connection 'LegacyInventorySystem' exists (40 pts)
2. Type is 'generic' (20 pts)
3. URL and Username match requirements (20 pts)
4. 'Grant access permission to all pipelines' is enabled (20 pts)

Anti-gaming:
- The connection must be retrievable via API (proves it was actually saved)
- Checks specifically for the name requested
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_legacy_service_connection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'LegacyInventorySystem')
    expected_type = metadata.get('expected_type', 'generic')
    expected_url = metadata.get('expected_url', 'https://inventory.local/api/v1')
    expected_username = metadata.get('expected_username', 'svc_ado_connect')

    # Copy result file from Windows path
    # Note: The agent environment is Windows, paths use backslashes or forward slashes depending on implementation.
    # We try typical locations.
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Adjust path based on how it's saved in export_result.ps1
        remote_path = r"C:\Users\Docker\task_results\result.json"
        copy_from_env(remote_path, temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result file: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve verification results. Did the export script run? Error: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Existence (40 pts)
    if not result.get('exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Service connection '{expected_name}' was not found in the project."
        }
    
    score += 40
    feedback.append(f"Service connection '{expected_name}' created.")

    # 2. Check Type (20 pts)
    actual_type = result.get('type', '').lower()
    if actual_type == expected_type.lower():
        score += 20
        feedback.append("Correct connection type (Generic).")
    else:
        feedback.append(f"Incorrect type: expected '{expected_type}', got '{actual_type}'.")

    # 3. Check Configuration (URL/User) (20 pts)
    actual_url = result.get('url', '').rstrip('/')
    target_url = expected_url.rstrip('/')
    actual_user = result.get('username', '')
    
    config_score = 0
    if actual_url == target_url:
        config_score += 10
    else:
        feedback.append(f"Incorrect URL: expected '{expected_url}', got '{actual_url}'.")
        
    if actual_user == expected_username:
        config_score += 10
    else:
        feedback.append(f"Incorrect Username: expected '{expected_username}', got '{actual_user}'.")
    
    score += config_score
    if config_score == 20:
        feedback.append("Configuration details correct.")

    # 4. Check Security/Pipelines Permission (20 pts)
    # This corresponds to "Grant access permission to all pipelines" checkbox
    is_authorized = result.get('is_authorized', False)
    if is_authorized:
        score += 20
        feedback.append("Pipeline access permissions granted correctly.")
    else:
        feedback.append("Failed: 'Grant access permission to all pipelines' was NOT checked.")

    # Final tally
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }