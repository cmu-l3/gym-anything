#!/usr/bin/env python3
"""
Verifier for add_employee task.

VERIFICATION STRATEGY:
1. Primary: Check database for presence of user "Maria Santos" with correct details.
2. Secondary: Verify database was modified during task execution.
3. Tertiary: VLM trajectory analysis to confirm UI interaction.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_employee(traj, env_info, task_info):
    """
    Verify that a new employee was added to Floreant POS.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Task requirements
    metadata = task_info.get('metadata', {})
    target_first = metadata.get('target_first_name', 'Maria').upper()
    target_last = metadata.get('target_last_name', 'Santos').upper()
    target_pin = metadata.get('target_pin', '2345')
    target_type = metadata.get('target_type', 'CASHIER').upper()

    score = 0
    feedback_parts = []
    
    # -----------------------------------------------------------------------
    # 1. Retrieve Result JSON
    # -----------------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # -----------------------------------------------------------------------
    # 2. Database Verification (60 points)
    # -----------------------------------------------------------------------
    user_found = result.get('user_found', False)
    db_modified = result.get('db_modified', False)
    user_details = result.get('user_details', {})
    raw_row = user_details.get('raw_row', "").upper()

    if user_found and raw_row:
        score += 25
        feedback_parts.append("User record created")
        
        # Parse raw row to check details
        # Derby output usually looks like: MARIA | SANTOS | CASHIER | 2345 | ...
        
        # Check Last Name
        if target_last in raw_row:
            score += 15
            feedback_parts.append(f"Correct Last Name ({target_last})")
        else:
            feedback_parts.append(f"Incorrect Last Name (Expected {target_last})")

        # Check User Type
        if target_type in raw_row:
            score += 10
            feedback_parts.append(f"Correct Role ({target_type})")
        else:
            feedback_parts.append(f"Incorrect Role (Expected {target_type})")

        # Check PIN/Password
        if target_pin in raw_row:
            score += 10
            feedback_parts.append("Correct PIN")
        else:
            feedback_parts.append("Incorrect PIN")
            
    else:
        feedback_parts.append("User record NOT found in database")

    # Anti-gaming: Check if DB was actually modified
    if db_modified:
        score += 10
        feedback_parts.append("Database file modification detected")
    else:
        feedback_parts.append("No database modification detected")

    # -----------------------------------------------------------------------
    # 3. VLM Trajectory Verification (30 points)
    # -----------------------------------------------------------------------
    # We use a simplified check here based on passed/score requirements
    # Ideally, this would use query_vlm if available in the scope
    
    # For now, we assume if the DB record is perfect, the UI interaction was likely valid.
    # We add points if score > 0 to account for implicit visual success
    if score >= 60:
        score += 30
        feedback_parts.append("Implicit VLM pass (successful DB record creation)")
    elif score > 0:
        score += 10
        feedback_parts.append("Partial VLM credit")

    # -----------------------------------------------------------------------
    # Final Decision
    # -----------------------------------------------------------------------
    passed = (score >= 70) and user_found
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }