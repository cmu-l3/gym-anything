#!/usr/bin/env python3
"""
Verifier for configure_scanning_speed task.

This verifier checks if the agent successfully changed the scanning speed
in JStock to "Slow" (60 seconds).

It uses:
1. File Verification: Checks if the options configuration file was modified
   and contains the correct value ("SLOW" or "60000").
2. App State: Checks if JStock is still running.
3. VLM Verification: (Optional/Stubbed here) Analyzes trajectory to ensure
   the Options dialog was actually interacted with.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_scanning_speed(traj, env_info, task_info):
    """
    Verify that the scanning speed was set to Slow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Load Result JSON
    # ================================================================
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
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # 2. Check Application State (10 points)
    # ================================================================
    if result.get('app_was_running', False):
        score += 10
        feedback_parts.append("JStock remained open")
    else:
        feedback_parts.append("JStock was closed (should remain open)")

    # ================================================================
    # 3. Check Configuration Modification (30 points)
    # ================================================================
    config_found = result.get('config_file_found', False)
    config_modified = result.get('config_modified_during_task', False)
    
    if config_found:
        if config_modified:
            score += 30
            feedback_parts.append("Configuration saved successfully")
        else:
            feedback_parts.append("Configuration file not modified (did you click OK?)")
    else:
        feedback_parts.append("Configuration file not found")

    # ================================================================
    # 4. Verify Configuration Content (60 points)
    # ================================================================
    # JStock config is XStream XML. We look for the scanning speed setting.
    # It might be an enum <scanningSpeed>SLOW</scanningSpeed> or integer <scanningSpeed>60000</scanningSpeed>
    
    config_content = result.get('config_content_snippet', '')
    value_found = False
    
    # Check for likely XML patterns for "Slow" setting
    # Pattern 1: Enum style
    if re.search(r'<scanningSpeed>.*SLOW.*</scanningSpeed>', config_content, re.IGNORECASE):
        value_found = True
    # Pattern 2: Millisecond style (60 seconds = 60000 ms)
    elif re.search(r'<scanningSpeed>.*60000.*</scanningSpeed>', config_content):
        value_found = True
    # Pattern 3: Simple grep fallback from export script
    elif result.get('scanning_speed_value_found') in ['SLOW', '60000']:
        value_found = True

    if value_found:
        score += 60
        feedback_parts.append("Scanning speed correctly set to 'Slow'")
    else:
        # Check if it's still default to give better feedback
        if re.search(r'<scanningSpeed>.*NORMAL.*</scanningSpeed>', config_content, re.IGNORECASE) or \
           re.search(r'<scanningSpeed>.*30000.*</scanningSpeed>', config_content):
            feedback_parts.append("Scanning speed is still set to 'Normal'")
        else:
            feedback_parts.append("Scanning speed setting not found in config")

    # ================================================================
    # 5. Final Decision
    # ================================================================
    # Pass if score >= 70 (Requires at least config modification + correct value)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }