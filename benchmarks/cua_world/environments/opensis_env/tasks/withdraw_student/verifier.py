#!/usr/bin/env python3
"""
Verifier for withdraw_student task.

Task: Withdraw student 'Maria Rodriguez' with:
    - Drop Date: 2025-01-15
    - Drop Code: Transferred

Verification Strategy:
1. PRIMARY: Database check (end_date set, drop_code correct).
2. SECONDARY: Anti-gaming check (ensure state changed from initial).
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_withdraw_student(traj, env_info, task_info):
    """
    Verify the student withdrawal.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_date = metadata.get('target_drop_date', '2025-01-15')
    target_code_keyword = metadata.get('target_drop_code_keyword', 'Transfer')

    # =========================================================================
    # Retrieve Data
    # =========================================================================
    
    # 1. Get Initial State (for anti-gaming)
    initial_state = {}
    temp_init = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/initial_state.json", temp_init.name)
        with open(temp_init.name, 'r') as f:
            initial_state = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read initial state: {e}")
    finally:
        if os.path.exists(temp_init.name):
            os.unlink(temp_init.name)

    # 2. Get Final Result
    result = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    # =========================================================================
    # Evaluate Criteria
    # =========================================================================
    
    score = 0
    feedback_parts = []
    
    end_date = result.get('end_date', '')
    drop_code_id = result.get('drop_code_id', '')
    drop_code_title = result.get('drop_code_title', '')
    
    # Handle "NULL" string from bash/mysql export
    if end_date == "NULL": end_date = ""
    if drop_code_id == "NULL": drop_code_id = ""
    if drop_code_title == "NULL": drop_code_title = ""

    # Criterion 1: Withdrawal Processed (End Date is set) [30 pts]
    if end_date and end_date != "NULL":
        score += 30
        feedback_parts.append("Student withdrawal processed (end date set)")
    else:
        feedback_parts.append("Student NOT withdrawn (end date is empty)")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": result
        }

    # Criterion 2: Correct Date [20 pts]
    # Allow simple string match or datetime parsing
    if end_date == target_date:
        score += 20
        feedback_parts.append(f"Correct drop date ({end_date})")
    else:
        feedback_parts.append(f"Incorrect drop date (Expected: {target_date}, Got: {end_date})")

    # Criterion 3: Drop Code Set [20 pts]
    if drop_code_id and drop_code_id != "NULL" and drop_code_id != "0":
        score += 20
        feedback_parts.append("Drop code selected")
    else:
        feedback_parts.append("No drop code selected")

    # Criterion 4: Correct Drop Reason (Transferred) [15 pts]
    if target_code_keyword.lower() in drop_code_title.lower():
        score += 15
        feedback_parts.append(f"Correct drop reason ({drop_code_title})")
    else:
        feedback_parts.append(f"Incorrect drop reason (Expected 'Transfer...', Got '{drop_code_title}')")

    # Criterion 5: Anti-Gaming / State Change [15 pts]
    # Check if initial state was indeed active (null end date)
    init_end = initial_state.get('initial_end_date')
    if init_end is None and end_date:
        score += 15
        feedback_parts.append("Confirmed new change (was active at start)")
    elif init_end == end_date:
        score = 0
        feedback_parts = ["ANTI-GAMING FAIL: State did not change from initial"]
    
    passed = score >= 85  # Requires correct date and reason code
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "end_date": end_date,
            "drop_code": drop_code_title,
            "initial_state": initial_state
        }
    }