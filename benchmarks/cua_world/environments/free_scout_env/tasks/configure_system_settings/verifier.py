#!/usr/bin/env python3
"""
Verifier for configure_system_settings task.
"""

import json
import tempfile
import os
import re

def verify_configure_system_settings(traj, env_info, task_info):
    """
    Verify system settings were configured correctly.
    
    Scoring:
    - Company Name: 40 points (exact match required)
    - Timezone: 35 points (exact match or standard variations)
    - Time Format: 25 points (must be 12-hour format)
    
    Anti-gaming:
    - Checks if values actually changed from initial state.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_company = metadata.get('expected_company_name', 'Pacific Northwest Medical Center - IT Support')
    expected_timezone = metadata.get('expected_timezone', 'America/Los_Angeles')

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

    score = 0
    feedback_parts = []
    
    # 1. Verify Company Name (40 pts)
    current_company = result.get('current_company_name', '').strip()
    changed_company = result.get('changed_company', False)
    
    if current_company == expected_company:
        score += 40
        feedback_parts.append("Company Name: Correct")
    elif expected_company.lower() in current_company.lower():
        score += 20
        feedback_parts.append(f"Company Name: Partial match ('{current_company}')")
    elif changed_company:
        score += 5
        feedback_parts.append(f"Company Name: Changed but incorrect ('{current_company}')")
    else:
        feedback_parts.append("Company Name: Not updated")

    # 2. Verify Timezone (35 pts)
    current_timezone = result.get('current_timezone', '').strip()
    changed_timezone = result.get('changed_timezone', False)
    
    if current_timezone == expected_timezone:
        score += 35
        feedback_parts.append("Timezone: Correct")
    elif current_timezone.lower() in [expected_timezone.lower(), "us/pacific", "pacific time"]:
        score += 35
        feedback_parts.append(f"Timezone: Correct ({current_timezone})")
    elif changed_timezone:
        score += 5
        feedback_parts.append(f"Timezone: Changed but incorrect ('{current_timezone}')")
    else:
        feedback_parts.append("Timezone: Not updated")

    # 3. Verify Time Format (25 pts)
    # We check if the format string implies 12-hour time (contains 'g', 'h', 'a', 'A')
    # vs 24-hour (contains 'G', 'H' without AM/PM)
    current_format = result.get('current_time_format', '')
    changed_format = result.get('changed_time_format', False)
    
    is_12h = False
    # Common PHP date format characters for 12-hour
    if any(char in current_format for char in ['a', 'A', 'h', 'g']):
        is_12h = True
    # Or strict numeric mapping if FreeScout uses IDs (unlikely, usually strings)
    elif "12" in current_format.lower() or "am" in current_format.lower() or "pm" in current_format.lower():
        is_12h = True
        
    if is_12h:
        score += 25
        feedback_parts.append("Time Format: Correct (12-hour)")
    elif changed_format:
        score += 5
        feedback_parts.append(f"Time Format: Changed but appears to be 24-hour ('{current_format}')")
    else:
        feedback_parts.append("Time Format: Not updated")

    # Anti-gaming check: Ensure at least one setting was actually modified
    any_changes = result.get('changed_company', False) or \
                  result.get('changed_timezone', False) or \
                  result.get('changed_time_format', False)
                  
    if not any_changes and score > 0:
        feedback_parts.append("WARNING: No changes detected from initial state.")
        # If the environment started in the target state by accident, we shouldn't fail, 
        # but in a fresh env this implies "do nothing".
        # For this specific task, we'll assume fresh env has defaults.
        # We penalize heavily if nothing changed.
        score = 0
        feedback_parts.append("FAIL: No settings were modified.")

    passed = score >= 90  # Require high precision for configuration tasks

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }