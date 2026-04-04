#!/usr/bin/env python3
"""
Verifier for record_mortgage_payment task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_mortgage_payment(traj, env_info, task_info):
    """
    Verify that the mortgage payment was recorded correctly.
    
    Expected Logic:
    1. Checking Account should decrease by full payment ($2,450.00).
    2. Mortgage Account (Liability) should increase (less negative) by principal only ($1,150.00).
    3. The difference ($1,300.00) must be accounted for (as an expense/fee), otherwise the system isn't balanced.
    
    Starting State:
    Checking: $15,000.00 (1,500,000 cents)
    Mortgage: -$345,000.00 (-34,500,000 cents)
    
    Target State:
    Checking: $12,550.00 (1,255,000 cents)
    Mortgage: -$343,850.00 (-34,385,000 cents)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_checking = metadata.get('expected_checking_balance', 1255000)
    expected_mortgage = metadata.get('expected_mortgage_balance', -34385000)
    
    # Load result
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
    
    # Check 1: File modified (10 pts)
    if result.get('file_modified'):
        score += 10
        feedback.append("Portfolio Saved")
    else:
        feedback.append("Portfolio NOT saved")
        
    # Check 2: Checking Balance (40 pts)
    actual_checking = result.get('checking_balance', 0)
    if actual_checking == expected_checking:
        score += 40
        feedback.append(f"Checking Balance Correct (${actual_checking/100:.2f})")
    else:
        diff = (actual_checking - expected_checking) / 100.0
        feedback.append(f"Checking Balance Incorrect (Off by ${diff:.2f})")
        
    # Check 3: Mortgage Balance (40 pts)
    actual_mortgage = result.get('mortgage_balance', 0)
    if actual_mortgage == expected_mortgage:
        score += 40
        feedback.append(f"Mortgage Balance Correct (${actual_mortgage/100:.2f})")
    else:
        diff = (actual_mortgage - expected_mortgage) / 100.0
        feedback.append(f"Mortgage Balance Incorrect (Off by ${diff:.2f})")
        
    # Check 4: Mechanics (10 pts)
    # If balances are correct, they must have done it right, but this checks for explicit expense recording
    if result.get('expense_txn_found') or result.get('transfer_found'):
        score += 10
        feedback.append("Transaction details verified")
        
    passed = score >= 90  # Requires balances to be exactly right
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }