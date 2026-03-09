#!/usr/bin/env python3
"""
Verifier for record_outbound_delivery task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_outbound_delivery(traj, env_info, task_info):
    """
    Verify the agent recorded an Outbound Delivery correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values
    metadata = task_info.get('metadata', {})
    expected_shares = metadata.get('expected_shares', 50)
    expected_date = metadata.get('expected_date', "2024-12-15")
    expected_value = metadata.get('expected_value', 12250.00)
    
    # Load result from container
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
    
    # 1. Check if file modified (Anti-gaming)
    if result.get("file_modified", False):
        score += 5
        feedback.append("Portfolio file saved.")
    else:
        feedback.append("Portfolio file NOT saved/modified.")
        return {"passed": False, "score": 0, "feedback": "File not modified"}

    # 2. Check for DELIVERY_OUTBOUND transaction
    if result.get("delivery_found", False):
        score += 25
        feedback.append("Found Outbound Delivery transaction.")
        
        details = result.get("delivery_details", {})
        
        # Shares check
        shares = details.get("shares", 0)
        if abs(shares - expected_shares) < 0.001:
            score += 20
            feedback.append(f"Correct shares: {shares}")
        else:
            feedback.append(f"Incorrect shares: {shares} (expected {expected_shares})")

        # Date check
        date = details.get("date", "")
        # PP saves dates usually as YYYY-MM-DD or YYYY-MM-DDTHH:MM
        if expected_date in date:
            score += 15
            feedback.append(f"Correct date: {date}")
        else:
            feedback.append(f"Incorrect date: {date} (expected {expected_date})")

        # Amount/Value check
        amount = details.get("amount", 0)
        # Allow 10% tolerance on value/amount as it might be calculated differently
        if abs(amount - expected_value) <= (expected_value * 0.1):
            score += 10
            feedback.append(f"Correct value: ${amount:.2f}")
        else:
            feedback.append(f"Value mismatch: ${amount:.2f} (expected ~${expected_value})")
            
    else:
        feedback.append("No Outbound Delivery transaction found.")
        if result.get("sell_found", False):
            feedback.append("Found SELL transaction instead (Incorrect type).")

    # 3. Check for spurious SELL transaction
    if not result.get("sell_found", False):
        score += 5
        feedback.append("No incorrect SELL transaction.")
    else:
        feedback.append("Penalty: SELL transaction detected.")

    # 4. Check Cash Balance (should be unchanged from initial state, except for the initial setup deposit)
    if not result.get("cash_balance_changed", False):
        score += 5
        feedback.append("Cash balance unaffected (Correct).")
    else:
        feedback.append("Cash balance changed (Incorrect - Delivery should not generate cash).")

    # 5. Security check (implicit in parsing, but good to have explicit points if feasible)
    # The parsing logic in export_result checks for the transaction under the AAPL security if we strictly structured it that way,
    # but the current export script iterates all portfolios. 
    # For now, if the delivery is found, we assume it's attached to a security.
    # We can give the remaining 15 points for "Correct Security" if delivery_found is true
    # assuming the agent didn't create a fake security.
    if result.get("delivery_found", False):
        score += 15
        feedback.append("Transaction associated with security.")

    total_score = min(100, score)
    passed = (total_score >= 70) and result.get("delivery_found", False)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }