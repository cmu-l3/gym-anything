#!/usr/bin/env python3
"""
Verifier for create_journal_entry task.
Verifies the existence and correctness of a double-entry accounting record.
"""

import json
import os
import logging
import tempfile
from decimal import Decimal

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_journal_entry(traj, env_info, task_info):
    """
    Verify the journal entry creation using database records exported from the environment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_amount = float(metadata.get('target_amount', 1250.00))
    debit_prefix = metadata.get('debit_account_prefix', '6155')
    credit_prefix = metadata.get('credit_account_prefix', '512')
    keywords = metadata.get('required_keywords', ["hydraulique", "réparation"])

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if entry exists (Critical)
    entry_found = result.get('entry_found', False)
    final_count = int(result.get('final_count', 0))
    initial_count = int(result.get('initial_count', 0))

    if not entry_found:
        if final_count > initial_count:
            return {"passed": False, "score": 10, "feedback": "A new entry was created, but it did not match the required date (2017-06-15)."}
        return {"passed": False, "score": 0, "feedback": "No journal entry found matching the criteria."}
    
    score += 20
    feedback_parts.append("Journal entry created on correct date")

    # Inspect entry details
    entry = result.get('entry', {})
    lines = entry.get('lines', [])

    if not lines:
        return {"passed": False, "score": score, "feedback": "Journal entry created but has no line items."}

    # 2. Verify Line Items (Debit/Credit/Accounts)
    has_correct_debit = False
    has_correct_credit = False
    has_correct_desc = False
    is_balanced = False

    total_debit = 0.0
    total_credit = 0.0

    for line in lines:
        # Parse values (handle strings from JSON if necessary)
        debit = float(line.get('debit') or 0.0)
        credit = float(line.get('credit') or 0.0)
        acct_num = str(line.get('account_number', ''))
        name = str(line.get('name', '')).lower()

        total_debit += debit
        total_credit += credit

        # Check description content
        if any(k in name for k in keywords):
            has_correct_desc = True

        # Check Debit Line
        if debit == target_amount and acct_num.startswith(debit_prefix):
            has_correct_debit = True
        
        # Check Credit Line
        if credit == target_amount and acct_num.startswith(credit_prefix):
            has_correct_credit = True

    # Check Balance
    if abs(total_debit - total_credit) < 0.01 and total_debit > 0:
        is_balanced = True

    # Scoring details
    if has_correct_debit:
        score += 20
        feedback_parts.append(f"Correct debit line (Acct {debit_prefix}, Amount {target_amount})")
    else:
        feedback_parts.append(f"Missing or incorrect debit line (Expected {debit_prefix}, {target_amount})")

    if has_correct_credit:
        score += 20
        feedback_parts.append(f"Correct credit line (Acct {credit_prefix}, Amount {target_amount})")
    else:
        feedback_parts.append(f"Missing or incorrect credit line (Expected {credit_prefix}, {target_amount})")

    if is_balanced:
        score += 20
        feedback_parts.append("Entry is balanced")
    else:
        feedback_parts.append(f"Entry unbalanced (Dr: {total_debit}, Cr: {total_credit})")

    if has_correct_desc:
        score += 20
        feedback_parts.append("Description contains required details")
    else:
        feedback_parts.append("Description missing required keywords")

    # Final decision
    passed = score >= 80  # Requires most components to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback_parts)
    }