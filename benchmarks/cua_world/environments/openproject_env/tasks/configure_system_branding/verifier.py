#!/usr/bin/env python3
"""
Verifier for configure_system_branding@1
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_system_branding(traj, env_info, task_info):
    """
    Verifies that global system settings were updated correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_app_title', 'Nexus Project Hub')
    expected_welcome_fragment = metadata.get('expected_welcome_text_fragment', 'Nexus Solutions')
    expected_date = metadata.get('expected_date_format', '%Y-%m-%d')
    expected_sow = metadata.get('expected_start_of_week', '1')

    # Load result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    settings = result.get('settings', {})
    if 'error' in settings:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving settings: {settings['error']}"}

    score = 0
    feedback_lines = []

    # 1. Check App Title (25 pts)
    actual_title = settings.get('app_title', '')
    if actual_title == expected_title:
        score += 25
        feedback_lines.append(f"✓ Application title correct: '{actual_title}'")
    else:
        feedback_lines.append(f"✗ Application title incorrect. Expected '{expected_title}', got '{actual_title}'")

    # 2. Check Welcome Text (25 pts)
    actual_welcome = settings.get('welcome_text', '')
    if expected_welcome_fragment in actual_welcome:
        score += 25
        feedback_lines.append(f"✓ Welcome text contains '{expected_welcome_fragment}'")
    else:
        feedback_lines.append(f"✗ Welcome text missing '{expected_welcome_fragment}'. Actual: '{actual_welcome}'")

    # 3. Check Date Format (25 pts)
    actual_date = settings.get('date_format', '')
    if actual_date == expected_date:
        score += 25
        feedback_lines.append(f"✓ Date format correct: '{actual_date}'")
    else:
        feedback_lines.append(f"✗ Date format incorrect. Expected '{expected_date}', got '{actual_date}'")

    # 4. Check Start of Week (25 pts)
    actual_sow = str(settings.get('start_of_week', ''))
    if actual_sow == expected_sow:
        score += 25
        feedback_lines.append(f"✓ Start of week correct: '{actual_sow}' (Monday)")
    else:
        feedback_lines.append(f"✗ Start of week incorrect. Expected '{expected_sow}', got '{actual_sow}'")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }