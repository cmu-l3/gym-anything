#!/usr/bin/env python3
"""
Verifier for create_custom_order_type task.
Verifies that the 'Curbside' order type exists in the Floreant POS database
and has the correct configuration flags.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_order_type(traj, env_info, task_info):
    """
    Verify the creation and configuration of the Curbside order type.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check existence
    if not result.get('order_type_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Order Type 'Curbside' was not found in the database. Ensure you saved it with the exact name."
        }

    score = 30
    feedback_parts = ["Order Type 'Curbside' created successfully (30 pts)"]
    
    # 3. Check configuration flags
    # Expected: Table=False(0), Guest=False(0), CustomerData=True(1), Prepaid=True(1)
    
    # Check Required Customer Data (CRITICAL)
    req_data = int(result.get('required_customer_data', 0))
    if req_data == 1:
        score += 20
        feedback_parts.append("Correctly set 'Require Customer Data' (20 pts)")
    else:
        feedback_parts.append("FAILED: 'Require Customer Data' should be checked")

    # Check Prepaid (CRITICAL)
    prepaid = int(result.get('prepaid', 0))
    if prepaid == 1:
        score += 20
        feedback_parts.append("Correctly set 'Prepaid' (20 pts)")
    else:
        feedback_parts.append("FAILED: 'Prepaid' should be checked")

    # Check Table Selection (Should be False for curbside)
    show_table = int(result.get('show_table_selection', 1)) # Default to 1 (bad) if missing
    if show_table == 0:
        score += 15
        feedback_parts.append("Correctly disabled 'Table Selection' (15 pts)")
    else:
        feedback_parts.append("FAILED: 'Show Table Selection' should be unchecked")

    # Check Guest Selection (Should be False for curbside)
    show_guest = int(result.get('show_guest_selection', 1)) # Default to 1 (bad) if missing
    if show_guest == 0:
        score += 15
        feedback_parts.append("Correctly disabled 'Guest Selection' (15 pts)")
    else:
        feedback_parts.append("FAILED: 'Show Guest Selection' should be unchecked")

    # 4. Determine Pass/Fail
    # Pass threshold: 70 points. This requires creation + at least the two critical flags (Data + Prepaid).
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }