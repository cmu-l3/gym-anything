#!/usr/bin/env python3
"""
Verifier for customize_email_templates task.

Checks the Rocket.Chat Accounts_Enrollment_Email setting via exported API data
to confirm the footer was added successfully without breaking the original URL placeholders.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_email_templates(traj, env_info, task_info):
    """
    Verify that the Enrollment Email setting was modified correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch expected text from task metadata
    metadata = task_info.get('metadata', {})
    required_url = metadata.get('required_handbook_url', 'handbook.rocketchat.local')
    required_confidentiality = metadata.get('required_confidentiality_text', 'Confidentiality Notice')

    # Copy the exported result JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract setting states
    setting_value = result.get("setting_value", "").strip()
    initial_value = result.get("initial_value", "").strip()
    
    score = 0
    feedback_parts = []
    
    # Check if the API successfully returned the setting value
    if not setting_value:
        return {"passed": False, "score": 0, "feedback": "Could not retrieve the Enrollment Email setting from Rocket.Chat."}

    # CRITERION 1: Was the setting modified at all? (10 points)
    if setting_value != initial_value:
        score += 10
        feedback_parts.append("Email template modified")
    else:
        feedback_parts.append("Email template remained completely unchanged")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Does it contain the required Handbook URL? (30 points)
    if required_url in setting_value:
        score += 30
        feedback_parts.append("Handbook link present")
    else:
        feedback_parts.append("Missing required handbook link")

    # CRITERION 3: Does it contain the Confidentiality Notice? (20 points)
    if required_confidentiality in setting_value:
        score += 20
        feedback_parts.append("Confidentiality notice present")
    else:
        feedback_parts.append("Missing confidentiality notice")

    # CRITERION 4: Anti-destructive check. Did they preserve the original placeholders? (40 points)
    # The default Rocket.Chat enrollment email contains `[Site_URL]`. 
    # If the user replaced the entire text instead of appending, this breaks the application workflow.
    if "[Site_URL]" in setting_value or "[URL]" in setting_value or "Site_URL" in setting_value:
        score += 40
        feedback_parts.append("Critical activation placeholders preserved")
    else:
        feedback_parts.append("CRITICAL FAILURE: Original activation link placeholders were removed!")

    # A perfect score is 100. 
    # We require a passing score of 70+, meaning if they wiped the placeholder, they max out at 60 and fail.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }