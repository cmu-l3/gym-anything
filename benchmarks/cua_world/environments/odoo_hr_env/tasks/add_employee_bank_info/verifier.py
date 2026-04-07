#!/usr/bin/env python3
"""
Verifier for add_employee_bank_info task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_employee_bank_info(traj, env_info, task_info):
    """
    Verifies that the agent added the correct bank details to the employee.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_employee = metadata.get('target_employee', 'Anita Oliver')
    expected_bank = metadata.get('expected_bank_name', 'Safe Bank')
    expected_acc = metadata.get('expected_acc_number', '9876543210')

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if employee was found (sanity check)
    if not result.get("employee_found"):
        return {"passed": False, "score": 0, "feedback": f"Critical: Employee '{expected_employee}' not found in database."}

    # 2. Check if ANY bank account is linked (30 points)
    if result.get("bank_account_linked"):
        score += 30
        feedback_parts.append("Bank account linked")
    else:
        feedback_parts.append("No bank account linked to employee")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Check Account Number (40 points)
    actual_acc = result.get("acc_number", "")
    # Normalize spaces for comparison
    if str(actual_acc).replace(" ", "") == str(expected_acc).replace(" ", ""):
        score += 40
        feedback_parts.append(f"Correct account number ({actual_acc})")
    else:
        feedback_parts.append(f"Incorrect account number: expected '{expected_acc}', got '{actual_acc}'")

    # 4. Check Bank Name (30 points)
    actual_bank = result.get("bank_name", "")
    if actual_bank and expected_bank.lower() in actual_bank.lower():
        score += 30
        feedback_parts.append(f"Correct bank name ({actual_bank})")
    else:
        feedback_parts.append(f"Incorrect bank name: expected '{expected_bank}', got '{actual_bank}'")

    # 5. Anti-gaming: Timestamp check
    # If the record was created BEFORE the task started, score is zeroed (reused old data)
    if not result.get("timestamp_check_passed", False):
        score = 0
        feedback_parts.append("FAIL: Bank record creation timestamp is older than task start time (anti-gaming)")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }