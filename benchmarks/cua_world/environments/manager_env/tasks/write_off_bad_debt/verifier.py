#!/usr/bin/env python3
"""
Verifier for Write Off Bad Debt Task
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_write_off_bad_debt(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_amount = float(metadata.get('write_off_amount', 500.00))
    
    # Copy result file
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

    # Parse Manager Data
    data = result.get('manager_data', {})
    accounts = data.get('accounts', [])
    credit_notes = data.get('credit_notes', [])
    customers = data.get('customers', [])

    score = 0
    feedback = []
    
    # 1. Check for "Bad Debts" Account (30 pts)
    bad_debt_account_id = None
    bad_debt_account_found = False
    
    # Normalize checking
    for acc in accounts:
        # Account object usually has Name and Key/UUID
        name = acc.get('Name', '').lower()
        if 'bad debt' in name:
            bad_debt_account_found = True
            bad_debt_account_id = acc.get('Key') # UUID
            break
            
    if bad_debt_account_found:
        score += 30
        feedback.append("Success: 'Bad Debts' account created.")
    else:
        feedback.append("Fail: 'Bad Debts' account not found in Chart of Accounts.")

    # 2. Check for Credit Note for Alfreds Futterkiste (20 pts)
    # First find customer UUID
    cust_id = None
    for c in customers:
        if 'Alfreds' in c.get('Name', ''):
            cust_id = c.get('Key')
            break
            
    target_cn = None
    if cust_id:
        # Find credit note linked to this customer
        # Credit Note object usually has 'Customer' field (UUID)
        for cn in credit_notes:
            if cn.get('Customer') == cust_id:
                target_cn = cn
                break
    
    if target_cn:
        score += 20
        feedback.append("Success: Credit Note for Alfreds Futterkiste found.")
    else:
        feedback.append("Fail: No Credit Note found for Alfreds Futterkiste.")

    # 3. Check Amount (10 pts)
    if target_cn:
        # Amount might be in 'Lines' sum or a top level field depending on API version
        # Usually calculated from lines
        lines = target_cn.get('Lines', [])
        total = sum(float(line.get('Amount', 0)) for line in lines)
        
        if abs(total - expected_amount) < 0.01:
            score += 10
            feedback.append(f"Success: Credit Note amount is {expected_amount}.")
        else:
            feedback.append(f"Fail: Credit Note amount {total} does not match expected {expected_amount}.")

        # 4. Check Allocation (40 pts) - CRITICAL
        # Must link to the bad debt account UUID
        allocated_correctly = False
        if bad_debt_account_id:
            for line in lines:
                # Line 'Account' field must match Expense Account UUID
                if line.get('Account') == bad_debt_account_id:
                    allocated_correctly = True
                    break
        
        if allocated_correctly:
            score += 40
            feedback.append("Success: Credit Note correctly allocated to Bad Debts expense account.")
        else:
            if not bad_debt_account_id:
                feedback.append("Fail: Cannot verify allocation because Bad Debt account is missing.")
            else:
                feedback.append("Fail: Credit Note is NOT allocated to the Bad Debts account (check line items).")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }