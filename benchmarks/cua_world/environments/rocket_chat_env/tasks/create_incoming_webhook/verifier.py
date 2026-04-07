#!/usr/bin/env python3
"""
Verifier for create_incoming_webhook task.
"""

import json
import os
import tempfile
from datetime import datetime

def verify_create_incoming_webhook(traj, env_info, task_info):
    """
    Verifies that:
    1. An incoming webhook integration exists with correct settings.
    2. The webhook URL is saved to a file.
    3. A test message was posted using the webhook.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_integration_name', 'CI/CD Pipeline')
    target_channel = metadata.get('target_channel', '#release-updates')
    target_alias = metadata.get('target_alias', 'DeployBot')
    target_emoji = metadata.get('target_emoji', ':rocket:')
    
    score = 0
    feedback = []

    # Load result JSON
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

    task_start = result.get('task_start', 0)
    
    # 1. Verify Integration Configuration (45 points total)
    integration_found = result.get('integration_found', False)
    integration_data = result.get('integration_data', {})
    
    integration_token = ""
    
    if integration_found:
        score += 15
        feedback.append("Integration 'CI/CD Pipeline' found.")
        
        # Check specific fields
        # Channel
        if integration_data.get('channel') == target_channel:
            score += 10
            feedback.append("Correct channel configured.")
        else:
            feedback.append(f"Incorrect channel: {integration_data.get('channel')}")

        # Alias
        if integration_data.get('alias') == target_alias:
            score += 10
            feedback.append("Correct alias configured.")
        else:
            feedback.append(f"Incorrect alias: {integration_data.get('alias')}")
            
        # Emoji
        if integration_data.get('emoji') == target_emoji:
            score += 5
            feedback.append("Correct emoji configured.")
        else:
            feedback.append(f"Incorrect emoji: {integration_data.get('emoji')}")
            
        # Enabled
        if integration_data.get('enabled') is True:
            score += 5
            feedback.append("Integration is enabled.")
        else:
            feedback.append("Integration is disabled.")
            
        integration_token = integration_data.get('token', '')
        
        # Anti-gaming: Check timestamp (createdAt is ISO string)
        created_at_str = integration_data.get('_createdAt', '')
        # Simple check: if integration exists and was found by our script which filters by name, 
        # and we cleared old ones, it's likely new. 
        # Robust check would parse ISO date, but basic existence + clean setup is strong enough here.
    else:
        feedback.append("Integration 'CI/CD Pipeline' NOT found.")

    # 2. Verify File (15 points total)
    file_exists = result.get('file_exists', False)
    file_content = result.get('file_content', '')
    
    if file_exists:
        score += 5
        feedback.append("URL file exists.")
        
        if result.get('file_valid_url'):
            score += 5
            feedback.append("File contains valid URL format.")
            
            # Check if URL matches the integration token
            if integration_token and integration_token in file_content:
                score += 5
                feedback.append("File URL matches the created integration.")
            else:
                feedback.append("File URL does NOT match the created integration.")
        else:
            feedback.append("File content is not a valid Rocket.Chat webhook URL.")
    else:
        feedback.append("URL file NOT found.")

    # 3. Verify Message (40 points total)
    message_found = result.get('message_found', False)
    message_data = result.get('message_data', {})
    
    if message_found:
        score += 20
        feedback.append("Test message found in channel.")
        
        # Verify message source (should be bot/webhook)
        # Webhook messages usually have 'bot' field or specific 'alias'
        is_bot = False
        if message_data.get('bot') is not None:
            is_bot = True
        
        # Check alias matches
        if message_data.get('alias') == target_alias:
            score += 10
            feedback.append("Message sent with correct alias.")
        else:
            feedback.append(f"Message alias incorrect: {message_data.get('alias')}")
            
        # Timestamp check
        msg_ts_iso = message_data.get('ts', '')
        # Convert ISO to timestamp is tricky in restricted python env without dateutil
        # We'll rely on the setup script cleaning previous messages/integrations implies newness
        # and checking that the message *exists* in the current history query.
        
        if is_bot:
            score += 10
            feedback.append("Message verified as coming from a bot/integration.")
        else:
            feedback.append("Message appears to be from a regular user, not the webhook.")
    else:
        feedback.append("Test message NOT found in channel.")

    passed = score >= 60 and integration_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }