#!/usr/bin/env python3
"""Verifier for record_cross_currency_transfer task."""

import json
import tempfile
import os

def verify_record_cross_currency_transfer(traj, env_info, task_info):
    """
    Verify that a cross-currency transfer was recorded correctly.
    Requires:
    1. TRANSFER_OUT from EUR account (2,500.00 EUR)
    2. TRANSFER_IN to USD account (2,725.00 USD)
    3. Transactions must be LINKED (Transfer, not separate ops)
    4. Correct date (2024-10-15)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
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

    # 1. Check for Transfer Out (20 pts)
    if result.get("transfer_out_found"):
        score += 20
        feedback.append("Source transaction (EUR) found")
    else:
        feedback.append("Source transaction (2,500.00 EUR) NOT found")

    # 2. Check for Transfer In (20 pts)
    if result.get("transfer_in_found"):
        score += 20
        feedback.append("Target transaction (USD) found")
    else:
        feedback.append("Target transaction (2,725.00 USD) NOT found")

    # 3. Check for Linkage (40 pts) - CRITICAL
    # If they are not linked, it's just a deposit + withdrawal, which breaks return calculations
    if result.get("transactions_linked"):
        score += 40
        feedback.append("Transactions are correctly linked")
    elif result.get("transfer_out_found") and result.get("transfer_in_found"):
        feedback.append("Transactions exist but are NOT linked (used Deposit/Withdraw instead of Transfer?)")
    else:
        feedback.append("Linkage check failed due to missing transactions")

    # 4. Check Date (10 pts)
    if result.get("date_match"):
        score += 10
        feedback.append("Date is correct")
    elif result.get("transfer_out_found"):
        feedback.append("Date incorrect")

    # 5. File Saved (10 pts)
    if result.get("file_modified"):
        score += 10
        feedback.append("Portfolio file saved")
    else:
        feedback.append("Portfolio file not saved")

    passed = score >= 80  # Requires Linkage + Transactions

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }