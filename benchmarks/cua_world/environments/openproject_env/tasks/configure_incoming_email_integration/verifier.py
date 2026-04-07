#!/usr/bin/env python3
"""
Verifier for configure_incoming_email_integration task.

Requirements:
1. Incoming emails enabled (30 pts)
2. API Key matches 'inbound-email-secret-v1' (40 pts)
3. Body delimiter includes '-- reply above this line --' (30 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_incoming_email(traj, env_info, task_info):
    """
    Verify OpenProject incoming email configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    expected_api_key = metadata.get('expected_api_key', 'inbound-email-secret-v1')
    expected_delimiter = metadata.get('expected_delimiter', '-- reply above this line --')

    # Load result from container
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

    settings = result.get('settings', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Check Enabled (30 pts)
    # The setup script specifically sets this to false/0 before the task
    is_enabled = settings.get('enabled', False)
    if is_enabled:
        score += 30
        feedback_parts.append("Incoming emails enabled")
    else:
        feedback_parts.append("Incoming emails NOT enabled")

    # 2. Check API Key (40 pts)
    # Strict string match required
    actual_api_key = str(settings.get('api_key', '')).strip()
    if actual_api_key == expected_api_key:
        score += 40
        feedback_parts.append("API key correct")
    else:
        feedback_parts.append(f"API key incorrect (expected '{expected_api_key}', got '{actual_api_key}')")

    # 3. Check Delimiter (30 pts)
    # We check for substring presence because there might be other delimiters
    actual_delimiters = str(settings.get('delimiters', ''))
    if expected_delimiter in actual_delimiters:
        score += 30
        feedback_parts.append("Body delimiter correct")
    else:
        feedback_parts.append(f"Body delimiter missing expected string")

    # Anti-gaming: Timestamp check
    # In a real rigorous verification we might check updated_on from Rails,
    # but since we reset values in setup_task.sh, simply having the correct values
    # implies action was taken.
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }