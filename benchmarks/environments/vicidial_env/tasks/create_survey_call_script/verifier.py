#!/usr/bin/env python3
"""
Verifier for create_survey_call_script task.

Verifies:
1. Script exists in DB with correct ID (NPS_TELECOM_2025)
2. Script attributes match (Name, Comments, Active=Y)
3. Script content (HTML) contains required dynamic tokens and NPS questions
4. Anti-gaming: Script count increased, indicating creation during task
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_survey_call_script(traj, env_info, task_info):
    """
    Verify creation of Vicidial NPS survey script.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # Extract data
    script_exists = result.get('script_exists', False)
    script_data = result.get('script_data', {})
    initial_count = int(result.get('initial_script_count', 0))
    final_count = int(result.get('final_script_count', 0))
    
    # 1. Script Existence (Gatekeeper)
    if not script_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Script NPS_TELECOM_2025 was not found in the database."
        }
    
    score += 15
    feedback_parts.append("Script created (15 pts)")

    # 2. Metadata Checks
    # Name
    if "Telecom NPS Customer Survey" in script_data.get('script_name', ''):
        score += 10
        feedback_parts.append("Correct script name (10 pts)")
    else:
        feedback_parts.append("Incorrect script name")

    # Active
    if script_data.get('active') == 'Y':
        score += 5
        feedback_parts.append("Script is active (5 pts)")
    else:
        feedback_parts.append("Script is NOT active")

    # Comments
    if len(script_data.get('script_comments', '')) > 5:
        score += 5
        feedback_parts.append("Comments present (5 pts)")
    else:
        feedback_parts.append("Comments missing")

    # 3. Content Analysis
    script_text = script_data.get('script_text', '')
    
    # Dynamic Tokens
    tokens = {
        "--A--first_name--B--": 10,
        "--A--last_name--B--": 10,
        "--A--phone_number--B--": 10
    }
    
    for token, pts in tokens.items():
        if token in script_text:
            score += pts
            feedback_parts.append(f"Token {token} found ({pts} pts)")
        else:
            feedback_parts.append(f"Missing token: {token}")

    # NPS Content Logic
    # 0-10 Scale
    has_scale = bool(re.search(r'0.*10|zero.*ten', script_text, re.IGNORECASE))
    has_rec = bool(re.search(r'recommend|likely', script_text, re.IGNORECASE))
    
    if has_scale and has_rec:
        score += 15
        feedback_parts.append("NPS question found (15 pts)")
    elif has_scale or has_rec:
        score += 7
        feedback_parts.append("Partial NPS question (7 pts)")
    else:
        feedback_parts.append("NPS question missing")

    # Follow-up
    if re.search(r'reason|why|because', script_text, re.IGNORECASE):
        score += 10
        feedback_parts.append("Follow-up question found (10 pts)")
    else:
        feedback_parts.append("Follow-up question missing")

    # Closing
    if re.search(r'thank|bye|closing|appreciate', script_text, re.IGNORECASE):
        score += 5
        feedback_parts.append("Closing found (5 pts)")
    else:
        feedback_parts.append("Closing missing")

    # Length Check
    if len(script_text) >= 200:
        score += 5
        feedback_parts.append("Length OK (5 pts)")
    else:
        feedback_parts.append(f"Script too short ({len(script_text)} chars)")

    # 4. Anti-Gaming Check
    # Ensure the script count actually increased, implying a NEW creation event
    if final_count > initial_count:
        feedback_parts.append("Count check passed")
    else:
        # If score is high but count didn't increase, they might have edited an existing one
        # (Though setup clears it, so this is unlikely unless setup failed silently)
        feedback_parts.append("Warning: Script count did not increase")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }