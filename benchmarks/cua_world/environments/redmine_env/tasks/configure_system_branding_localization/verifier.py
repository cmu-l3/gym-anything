#!/usr/bin/env python3
"""
Verifier for configure_system_branding_localization task.

Scoring Criteria:
1. Application Title (20 pts)
2. Welcome Text (20 pts)
3. Date Format (20 pts)
4. Time Format (20 pts)
5. User Display Format (20 pts)

Verification Method:
- Programmatic check of Redmine 'Settings' model via exported JSON.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_system_branding_localization(traj, env_info, task_info):
    """
    Verify that Redmine system settings match the required branding and localization configuration.
    """
    # 1. Setup - retrieve result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    current_settings = result.get("current_settings", {})
    metadata = task_info.get("metadata", {})
    
    score = 0
    feedback_parts = []
    
    # 3. Verify Criteria
    
    # Criterion 1: Application Title (20 pts)
    # Expected: "Orbital Operations"
    actual_title = current_settings.get("app_title", "")
    expected_title = metadata.get("expected_app_title", "Orbital Operations")
    
    if actual_title == expected_title:
        score += 20
        feedback_parts.append(f"Title correct ({actual_title})")
    else:
        feedback_parts.append(f"Title incorrect (Found: '{actual_title}', Expected: '{expected_title}')")

    # Criterion 2: Welcome Text (20 pts)
    # Expected: "Authorized Personnel Only. All activity is monitored."
    actual_welcome = current_settings.get("welcome_text", "")
    expected_welcome = metadata.get("expected_welcome_text", "Authorized Personnel Only. All activity is monitored.")
    
    # Allow for minor whitespace differences
    if expected_welcome.strip() in actual_welcome.strip():
        score += 20
        feedback_parts.append("Welcome text correct")
    else:
        feedback_parts.append(f"Welcome text incorrect (Found: '{actual_welcome}')")

    # Criterion 3: Date Format (20 pts)
    # Expected: "%Y-%m-%d" (ISO 8601)
    actual_date = current_settings.get("date_format", "")
    expected_date = metadata.get("expected_date_format", "%Y-%m-%d")
    
    if actual_date == expected_date:
        score += 20
        feedback_parts.append("Date format correct")
    else:
        feedback_parts.append(f"Date format incorrect (Found: '{actual_date}', Expected: '{expected_date}')")

    # Criterion 4: Time Format (20 pts)
    # Expected: "%H:%M" (24-hour)
    actual_time = current_settings.get("time_format", "")
    expected_time = metadata.get("expected_time_format", "%H:%M")
    
    if actual_time == expected_time:
        score += 20
        feedback_parts.append("Time format correct")
    else:
        feedback_parts.append(f"Time format incorrect (Found: '{actual_time}', Expected: '{expected_time}')")

    # Criterion 5: User Format (20 pts)
    # Expected: "lastname_coma_firstname"
    actual_user = current_settings.get("user_format", "")
    expected_user = metadata.get("expected_user_format", "lastname_coma_firstname")
    
    if str(actual_user) == expected_user:
        score += 20
        feedback_parts.append("User format correct")
    else:
        feedback_parts.append(f"User format incorrect (Found: '{actual_user}', Expected: '{expected_user}')")

    # 4. Final Assessment
    # Threshold: 80 points (allows one mistake, but branding/security text usually critical)
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
        "details": {
            "actual_settings": current_settings,
            "expected_settings": metadata
        }
    }