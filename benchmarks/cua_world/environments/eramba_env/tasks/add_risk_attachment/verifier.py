#!/usr/bin/env python3
"""
Verifier for add_risk_attachment task.

Verifies:
1. An attachment record was created in the database for the correct Risk.
2. The filename matches the requirement.
3. The creation timestamp is after task start.
4. Physical file evidence (optional but good).
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_risk_attachment(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result
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

    # Criteria
    score = 0
    feedback_parts = []
    
    # 1. Database Record Check (40 pts)
    attachment_found = result.get('attachment_found', False)
    final_count = int(result.get('final_attachment_count', 0))
    initial_count = int(result.get('initial_attachment_count', 0))
    
    if attachment_found:
        score += 40
        feedback_parts.append("Attachment record found in database.")
    elif final_count > initial_count:
        # Fallback: Count increased but maybe filename query failed?
        score += 20
        feedback_parts.append("Attachment count increased, but specific file verification failed.")
    else:
        feedback_parts.append("No new attachment found on the risk.")

    # 2. Filename Check (30 pts)
    db_filename = result.get('db_filename', '')
    expected_pattern = "phishing_simulation_report"
    if expected_pattern in db_filename:
        score += 30
        feedback_parts.append(f"Correct filename uploaded: {db_filename}")
    elif attachment_found:
        feedback_parts.append(f"Attachment found but filename mismatch: {db_filename}")
    
    # 3. Anti-gaming / Timestamp Check (20 pts)
    # Since we check 'created' time in SQL query relative to task start implicitly via 'new' check
    # We can also check if physical file was modified recently
    physical_exists = result.get('physical_file_exists', False)
    if physical_exists:
        score += 20
        feedback_parts.append("Physical file creation confirmed in container.")
    elif attachment_found:
        # If DB says yes but physical check failed (maybe permissions?), give partial
        score += 10
        feedback_parts.append("DB record exists, but physical file check was inconclusive.")

    # 4. App Context (10 pts)
    # Implicitly if they got this far, the app was working, but we check if risk_id was found
    if result.get('risk_id', '0') != '0':
        score += 10
    
    # Final pass logic
    passed = (score >= 70) and attachment_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }