#!/usr/bin/env python3
"""
Verifier for integrate_crm_iframe_script task.

Checks:
1. Script 'ORDERFLOW' exists and is active.
2. Script content contains an <iframe> with the correct URL.
3. Script content contains the correct Vicidial variables.
4. Campaign 'SALES_Q1' is assigned to 'ORDERFLOW'.
5. Campaign 'SALES_Q1' is set to auto-launch the script.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_integrate_crm_iframe_script(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_url_base = metadata.get('expected_url_base', 'https://orderflow.internal/lookup')
    
    # Vicidial variables are specific: --A--var--B--
    expected_vars = metadata.get('expected_vars', ["--A--phone_number--B--", "--A--user--B--"])

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
    
    script_exists = result.get('script_exists', False)
    script_text = result.get('script_text', '')
    script_active = result.get('script_active', 'N')
    campaign_script = result.get('campaign_script', '')
    get_call_launch = result.get('get_call_launch', '')

    # Criterion 1: Script Created (10 pts)
    if script_exists:
        score += 10
        feedback_parts.append("Script 'ORDERFLOW' created")
        if script_active == 'Y':
            score += 5
            feedback_parts.append("Script is active")
    else:
        feedback_parts.append("Script 'ORDERFLOW' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Iframe Implementation (15 pts)
    # Check for <iframe...
    if "<iframe" in script_text.lower():
        score += 15
        feedback_parts.append("Iframe tag found")
    else:
        feedback_parts.append("No <iframe> tag in script")

    # Criterion 3: URL Correctness (15 pts)
    if expected_url_base in script_text:
        score += 15
        feedback_parts.append("Correct URL base")
    else:
        feedback_parts.append(f"URL missing '{expected_url_base}'")

    # Criterion 4: Variables (20 pts)
    vars_found = 0
    for var in expected_vars:
        if var in script_text:
            vars_found += 1
        else:
            feedback_parts.append(f"Missing variable {var}")
    
    if vars_found == len(expected_vars):
        score += 20
        feedback_parts.append("All variables present")
    elif vars_found > 0:
        score += 10
        feedback_parts.append("Some variables present")

    # Criterion 5: Campaign Assignment (15 pts)
    if campaign_script == "ORDERFLOW":
        score += 15
        feedback_parts.append("Campaign assigned to script")
    else:
        feedback_parts.append(f"Campaign script is '{campaign_script}', expected 'ORDERFLOW'")

    # Criterion 6: Auto-Launch Config (20 pts)
    if get_call_launch == "SCRIPT":
        score += 20
        feedback_parts.append("Get Call Launch set to SCRIPT")
    else:
        feedback_parts.append(f"Get Call Launch is '{get_call_launch}', expected 'SCRIPT'")

    passed = score >= 70 and script_exists and campaign_script == "ORDERFLOW"

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }