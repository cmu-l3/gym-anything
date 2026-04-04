#!/usr/bin/env python3
"""
Verifier for consolidate_duplicate_patients task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_duplicate_patients(traj, env_info, task_info):
    """
    Verifies that:
    1. The Master record (P00801) still exists.
    2. The Master record now contains the phone number '555-0199'.
    3. The Master record still contains the address '452 Oak Avenue'.
    4. The Duplicate record (P00802) has been deleted.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_phone = metadata.get('expected_phone', '555-0199')
    expected_address_start = "452 Oak Avenue" # Start of address string

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
    feedback = []
    
    # 1. Check Master Exists (20 pts)
    if result.get('master_exists', False):
        score += 20
        feedback.append("Master record preserved.")
    else:
        feedback.append("CRITICAL: Master record (P00801) was deleted or lost.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Check Duplicate Deleted (40 pts)
    if result.get('duplicate_deleted', False):
        score += 40
        feedback.append("Duplicate record successfully deleted.")
    else:
        feedback.append("Duplicate record (P00802) still exists.")

    # 3. Check Data Consolidation (40 pts)
    # Check Phone
    actual_phone = result.get('master_phone', '')
    if expected_phone in actual_phone:
        score += 20
        feedback.append(f"Phone number '{expected_phone}' successfully transferred.")
    else:
        feedback.append(f"Master record missing phone number (Expected '{expected_phone}', Got '{actual_phone}').")

    # Check Address (Integrity check)
    actual_address = result.get('master_address', '')
    if expected_address_start in actual_address:
        score += 20
        feedback.append("Address data preserved.")
    else:
        feedback.append(f"Master record address modified/lost (Got '{actual_address}').")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }