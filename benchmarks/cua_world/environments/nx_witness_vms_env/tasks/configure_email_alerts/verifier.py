#!/usr/bin/env python3
"""
Verifier for configure_email_alerts task.
Checks if the SMTP settings in the Nx Witness VMS system match the requirements.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_email_alerts(traj, env_info, task_info):
    """
    Verifies that the agent correctly configured the SMTP settings via API.
    """
    # 1. Setup access to file from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_settings', {
        "smtpHost": "smtp.securecorp.net",
        "smtpPort": 587,
        "smtpConnectionType": "tls",
        "emailFrom": "vms-alerts@securecorp.net",
        "smtpUser": "vms-alerts@securecorp.net",
        "smtpPassword": "S3cur3Ma!l#2024"
    })
    
    scoring_weights = metadata.get('scoring', {
        "smtpHost": 18,
        "smtpPort": 14,
        "smtpConnectionType": 14,
        "emailFrom": 18,
        "smtpUser": 18,
        "smtpPassword": 18
    })

    # 3. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve or parse task result: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Check for errors in extraction
    if result.get('error'):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during result export in environment: {result.get('error')}"
        }

    # 5. Evaluate each field
    score = 0
    feedback_parts = []
    
    # Check Host
    actual_host = str(result.get('smtpHost', '')).strip()
    if actual_host == expected['smtpHost']:
        score += scoring_weights['smtpHost']
        feedback_parts.append("✅ Host correct")
    else:
        feedback_parts.append(f"❌ Host incorrect (Found: '{actual_host}')")

    # Check Port
    # Handle int/string difference safely
    try:
        actual_port = int(result.get('smtpPort', 0))
        expected_port = int(expected['smtpPort'])
        if actual_port == expected_port:
            score += scoring_weights['smtpPort']
            feedback_parts.append("✅ Port correct")
        else:
            feedback_parts.append(f"❌ Port incorrect (Found: {actual_port})")
    except ValueError:
        feedback_parts.append(f"❌ Port invalid")

    # Check Connection Type
    actual_conn = str(result.get('smtpConnectionType', '')).lower()
    if actual_conn == expected['smtpConnectionType'].lower():
        score += scoring_weights['smtpConnectionType']
        feedback_parts.append("✅ Connection type correct")
    else:
        feedback_parts.append(f"❌ Connection type incorrect (Found: '{actual_conn}')")

    # Check Sender Email
    actual_from = str(result.get('emailFrom', '')).strip()
    if actual_from == expected['emailFrom']:
        score += scoring_weights['emailFrom']
        feedback_parts.append("✅ Sender email correct")
    else:
        feedback_parts.append(f"❌ Sender email incorrect (Found: '{actual_from}')")

    # Check User
    actual_user = str(result.get('smtpUser', '')).strip()
    if actual_user == expected['smtpUser']:
        score += scoring_weights['smtpUser']
        feedback_parts.append("✅ Username correct")
    else:
        feedback_parts.append(f"❌ Username incorrect (Found: '{actual_user}')")

    # Check Password
    actual_pass = str(result.get('smtpPassword', ''))
    if actual_pass == expected['smtpPassword']:
        score += scoring_weights['smtpPassword']
        feedback_parts.append("✅ Password correct")
    else:
        feedback_parts.append("❌ Password incorrect")

    # 6. Anti-gaming check: Ensure at least one value is set
    # (The score logic implicitly handles this, but explicit feedback helps)
    if score == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No settings were configured correctly. Did you use the API to PATCH /rest/v1/system/settings?"
        }

    # 7. Final Result
    passed = score >= 70  # Threshold as defined in task description
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ", ".join(feedback_parts)
    }