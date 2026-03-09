#!/usr/bin/env python3
"""
Verifier for issue_financial_credit_note task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_issue_financial_credit_note(traj, env_info, task_info):
    """
    Verifies:
    1. 'Volume Discounts' account created in Chart of Accounts.
    2. Credit Note exists for 'Alfreds Futterkiste'.
    3. Amount is 500.00.
    4. Allocation is to 'Volume Discounts' (implies no inventory item used).
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback = []
    
    # 1. Account Creation (25 pts)
    if result.get('account_created'):
        score += 25
        feedback.append("Account 'Volume Discounts' created.")
    else:
        feedback.append("Account 'Volume Discounts' NOT found.")

    # 2. Credit Note Existence & Customer (20 pts)
    if result.get('correct_customer'):
        score += 20
        feedback.append("Credit Note for 'Alfreds Futterkiste' found.")
    else:
        feedback.append("Credit Note for correct customer NOT found.")

    # 3. Correct Amount (15 pts)
    if result.get('correct_amount'):
        score += 15
        feedback.append("Amount 500.00 matches.")
    else:
        feedback.append("Amount 500.00 NOT found.")

    # 4. Correct Allocation / No Inventory Item (40 pts)
    # This is the core accounting test: did they map it to the financial account directly?
    if result.get('allocated_correctly'):
        score += 40
        feedback.append("Correctly allocated to 'Volume Discounts' (Financial Credit).")
    elif result.get('credit_note_found'):
        feedback.append("Credit Note exists but allocation incorrect (possibly used Inventory Item).")
    else:
        feedback.append("Allocation not verified (Credit Note missing).")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }