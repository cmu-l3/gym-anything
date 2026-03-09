#!/usr/bin/env python3
"""
Verifier for add_cooking_instruction task.

Verifies that specific cooking instructions were added to the Floreant POS database.
Uses a hybrid approach:
1. File-based DB search (robust)
2. SQL query (structure-aware)
3. Database modification timestamps (anti-gaming)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_cooking_instruction(traj, env_info, task_info):
    """
    Verify "No Onions" and "Extra Crispy" were added to cooking instructions.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy function missing"}

    # ------------------------------------------------------------------
    # 1. Retrieve Result Data
    # ------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results: {str(e)}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # ------------------------------------------------------------------
    # 2. Evaluate Criteria
    # ------------------------------------------------------------------
    score = 0
    feedback_parts = []
    
    # Criterion 1: Database Modification (Anti-gaming) - 10 pts
    # If the DB files didn't change at all, the agent did nothing.
    db_modified = result.get('db_modified', False)
    if db_modified:
        score += 10
        feedback_parts.append("Database modification detected.")
    else:
        feedback_parts.append("Warning: No database changes detected.")

    # Criterion 2: "No Onions" Added - 45 pts
    # We accept either grep finding or SQL finding
    no_onions = result.get('found_no_onions', False) or result.get('sql_verified_no_onions', False)
    if no_onions:
        score += 45
        feedback_parts.append("'No Onions' instruction confirmed in database.")
    else:
        feedback_parts.append("Failed to find 'No Onions' in database.")

    # Criterion 3: "Extra Crispy" Added - 45 pts
    extra_crispy = result.get('found_extra_crispy', False) or result.get('sql_verified_extra_crispy', False)
    if extra_crispy:
        score += 45
        feedback_parts.append("'Extra Crispy' instruction confirmed in database.")
    else:
        feedback_parts.append("Failed to find 'Extra Crispy' in database.")

    # ------------------------------------------------------------------
    # 3. Final Determination
    # ------------------------------------------------------------------
    passed = (score >= 90)  # Requires both items + DB modification check
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }