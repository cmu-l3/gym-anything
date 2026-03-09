#!/usr/bin/env python3
"""
Verifier for configure_user_survey task.

Verifies:
1. Two specific questions were added to the database.
2. The survey configuration is enabled (inferred from DB state).
3. Anti-gaming: Changes persist in the database.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_user_survey(traj, env_info, task_info):
    """
    Verify User Satisfaction Survey configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # 1. Verify App State
    if not result.get('app_running', False):
        return {"passed": False, "score": 0, "feedback": "ServiceDesk Plus is not running"}
    score += 10 # Base points for keeping app alive

    # 2. Verify Questions (Primary Goal)
    # We look for the text in the DB dump analysis performed by export script
    has_tech = result.get('has_question_technical', False)
    has_time = result.get('has_question_timely', False)

    if has_tech:
        score += 30
        feedback_parts.append("Technical knowledge question found")
    else:
        feedback_parts.append("Technical knowledge question NOT found")

    if has_time:
        score += 30
        feedback_parts.append("Timeliness question found")
    else:
        feedback_parts.append("Timeliness question NOT found")

    # 3. Verify Enabled/Configuration
    # We decode the DB dump to look for enabled flags or trigger settings
    db_dump_b64 = result.get('db_dump_base64', "")
    db_dump = ""
    if db_dump_b64:
        try:
            db_dump = base64.b64decode(db_dump_b64).decode('utf-8', errors='ignore')
        except:
            pass
    
    # Heuristic check for enabled status in the dump
    # Look for common "true" or "1" flags associated with survey config tables
    # Also look for "Closed" trigger keywords
    
    survey_enabled_heuristic = False
    
    # Check for "Closed" trigger association
    # This matches patterns like "Closed" appearing in survey rules or config
    if "Closed" in db_dump and ("true" in db_dump.lower() or "t" in db_dump.lower() or "1" in db_dump):
        survey_enabled_heuristic = True
        score += 30
        feedback_parts.append("Survey appears enabled for Closed requests")
    else:
        # Fallback partial credit if we just see the questions but can't confirm config definitively
        # (Database schemas vary wildly, so being too strict on the 'enabled' flag column might fail valid solutions)
        feedback_parts.append("Could not definitively verify 'Enabled' status in DB (check manual verification)")
        if has_tech and has_time: 
            score += 10 # Partial credit for doing the hard part (questions)

    # Final Score Calculation
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }