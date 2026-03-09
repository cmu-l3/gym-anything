#!/usr/bin/env python3
"""
Verifier for create_chart_account task.
Verifies that the agent created account 6227 with the correct name.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_chart_account(traj, env_info, task_info):
    """
    Verify creation of the specific chart of accounts entry.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_number = metadata.get('expected_number', '6227')
    kw1 = metadata.get('expected_name_keyword_1', 'certification').lower()
    kw2 = metadata.get('expected_name_keyword_2', 'biologique').lower()

    # Retrieve result JSON
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
    
    # 1. Primary Check: Account Exists (30 pts)
    account_found = result.get('account_found', False)
    details = result.get('account_details', {})
    acc_number = details.get('number', '')
    
    if account_found and acc_number == expected_number:
        score += 30
        feedback_parts.append(f"Account {expected_number} created successfully")
    else:
        feedback_parts.append(f"Account {expected_number} NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Name Verification (30 pts split)
    acc_name = details.get('name', '').lower()
    if kw1 in acc_name:
        score += 20
        feedback_parts.append(f"Name contains '{kw1}'")
    else:
        feedback_parts.append(f"Name missing '{kw1}'")

    if kw2 in acc_name:
        score += 10
        feedback_parts.append(f"Name contains '{kw2}'")
    else:
        feedback_parts.append(f"Name missing '{kw2}'")

    # 3. Count Verification (10 pts)
    # Anti-gaming: Ensure the total count actually increased
    initial = int(result.get('initial_count', 0))
    final = int(result.get('final_count', 0))
    if final > initial:
        score += 10
        feedback_parts.append("Account count increased")
    else:
        feedback_parts.append("Account count did not increase (modified existing?)")

    # 4. Anti-gaming / Timestamp Check (15 pts)
    # Since we deleted the account in setup, existence implies creation.
    # We double check that created_at is populated.
    if details.get('created_at'):
        score += 15
        feedback_parts.append("Creation timestamp valid")
    else:
        feedback_parts.append("No creation timestamp found")

    # 5. App State (15 pts)
    if result.get('app_running', False):
        score += 15
        feedback_parts.append("Application still running")
    else:
        feedback_parts.append("Application was closed")

    # Pass Threshold: 60 points AND Account Found
    passed = (score >= 60) and account_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }