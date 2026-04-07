#!/usr/bin/env python3
"""
Verifier for create_custom_slash_command task.
Checks if the Slash Command was created in Rocket.Chat via API data export.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_create_custom_slash_command(traj, env_info, task_info):
    """
    Verifies that the user created a slash command 'deploy-status' with specific settings.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_command = metadata.get('expected_command', 'deploy-status')
    expected_url = metadata.get('expected_url', 'http://internal-tools.local/api/deploy/status')
    expected_method = metadata.get('expected_method', 'GET')
    expected_desc = metadata.get('expected_description', 'Check the status of the current deployment')

    # 2. Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data from environment."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Verify Logic
    score = 0
    feedback = []
    
    integration = result_data.get('found_integration')
    task_start_time = result_data.get('task_start_time', 0)

    # Criterion 1: Integration exists (40 pts)
    if not integration:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Slash command '/{expected_command}' was not found in the system."
        }
    
    score += 40
    feedback.append(f"Slash command '/{expected_command}' found.")

    # Criterion 2: Correct URL (30 pts)
    # Note: Rocket.Chat might store urls in 'urls' array or 'url' field depending on version/type
    # The API usually returns 'urls' as a list for webhooks, but let's check both
    actual_url = integration.get('url') or (integration.get('urls')[0] if integration.get('urls') else "")
    
    if actual_url == expected_url:
        score += 30
        feedback.append("Target URL is correct.")
    else:
        feedback.append(f"Incorrect URL. Expected '{expected_url}', got '{actual_url}'.")

    # Criterion 3: Correct Method (10 pts)
    # The API often returns methods like 'GET', 'POST'
    # Sometimes stored in 'method'
    actual_method = integration.get('method', '').upper()
    if actual_method == expected_method.upper():
        score += 10
        feedback.append("Request method is correct.")
    else:
        feedback.append(f"Incorrect method. Expected '{expected_method}', got '{actual_method}'.")

    # Criterion 4: Enabled State (10 pts)
    if integration.get('enabled') is True:
        score += 10
        feedback.append("Integration is enabled.")
    else:
        feedback.append("Integration is created but disabled.")

    # Criterion 5: Description/Alias (10 pts)
    # Description might be in 'description' or 'name' or 'alias' depending on exact UI field mapping
    actual_desc = integration.get('description', '')
    actual_alias = integration.get('alias', '') # Sometimes description is put in alias by users
    
    if expected_desc.lower() in actual_desc.lower() or expected_desc.lower() in actual_alias.lower():
        score += 10
        feedback.append("Description matches.")
    else:
        feedback.append("Description text mismatch or missing.")

    # Anti-gaming: Timestamp check
    # Rocket.Chat timestamps are typically ISO strings in '_createdAt'
    created_at_str = integration.get('_createdAt', '')
    is_new = False
    if created_at_str:
        try:
            # Parse ISO format like '2023-10-27T10:00:00.000Z'
            # Simplified parsing or just check raw string if difficult in restricted python
            # We'll use a rough check if datetime parsing fails
            dt_object = datetime.strptime(created_at_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
            created_ts = dt_object.timestamp()
            
            # Allow some clock skew (e.g. 60s)
            if created_ts > (task_start_time - 60):
                is_new = True
        except ValueError:
            # Fallback if parsing fails (e.g. different format): just assume valid if we found it
            # and it wasn't deleted in setup
            logger.warning(f"Could not parse timestamp {created_at_str}, skipping strict time check")
            is_new = True
    
    if not is_new:
        feedback.append("WARNING: Integration appears to be created before task started.")
        # We might penalize here, but since we delete in setup, existence implies recreation.
        # We will deduct 50% of points if it looks old to prevent reuse.
        score = int(score * 0.5)

    passed = (score >= 70) and (actual_url == expected_url)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }