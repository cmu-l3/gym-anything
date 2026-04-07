#!/usr/bin/env python3
"""
Verifier for create_cash_journal@1
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_cash_journal(traj, env_info, task_info):
    """
    Verifies the creation of a Cash Journal entry in iDempiere.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    task_start = result.get('task_start', 0)
    record = result.get('latest_cash_record')
    lines = result.get('cash_lines', [])
    
    if not record:
        return {"passed": False, "score": 0, "feedback": "No Cash Journal records found in database."}

    # 3. Anti-Gaming Check (Timestamp)
    # iDempiere stores 'created' timestamp. We compare epoch.
    # Note: DB time might differ slightly from system time, but 'created_epoch' comes from DB query
    created_epoch = float(record.get('created_epoch', 0))
    if created_epoch < task_start:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Latest record was created before task started. (Created: {created_epoch}, Task Start: {task_start})"
        }

    score = 0
    feedback = []

    # 4. Scoring Criteria
    
    # Criterion 1: Record Exists (implied by passing anti-gaming) -> 15 pts
    score += 15
    feedback.append("New Cash Journal record created.")

    # Criterion 2: Statement Date (2024-12-15) -> 10 pts
    expected_date = task_info.get('metadata', {}).get('expected_date', '2024-12-15')
    if record.get('statementdate') == expected_date:
        score += 10
        feedback.append(f"Correct Statement Date ({expected_date}).")
    else:
        feedback.append(f"Incorrect Date: expected {expected_date}, got {record.get('statementdate')}.")

    # Criterion 3: Description ("Week 50") -> 5 pts
    expected_desc = task_info.get('metadata', {}).get('expected_desc_fragment', 'Week 50')
    desc = record.get('description', '') or ''
    if expected_desc.lower() in desc.lower():
        score += 5
        feedback.append("Description contains required text.")
    else:
        feedback.append(f"Description missing '{expected_desc}'.")

    # Criterion 4: Document Status (Completed/CO) -> 10 pts
    # Expected status 'CO' (Completed)
    expected_status = task_info.get('metadata', {}).get('expected_status', 'CO')
    if record.get('docstatus') == expected_status:
        score += 10
        feedback.append("Document is Completed.")
    else:
        feedback.append(f"Document not completed (Status: {record.get('docstatus')}).")

    # Criterion 5 & 6: Line Items
    # We look for specific charges with specific amounts.
    # Amounts are negative for expenses in Cash Journal.
    
    # Helpers
    def find_line(charge_name_part, amount_abs):
        for line in lines:
            line_amt = float(line.get('amount', 0))
            line_charge = line.get('charge_name', '') or ''
            # Check charge name
            if charge_name_part.lower() in line_charge.lower():
                # Check amount (allow sign flip errors or small float diffs, strictness depends on rubric)
                # Task says -75. We check if abs(amount) is close to 75.
                if math.isclose(abs(line_amt), amount_abs, rel_tol=0.01):
                    return True, line_amt
        return False, 0

    # Freight Line (Charge: Freight, Amount: 75) -> 30 pts (20 for existence, 10 for amount implied)
    # Breaking down: 20 for correct charge type, 10 for correct amount logic
    found_freight, freight_amt = find_line("Freight", 75.00)
    if found_freight:
        score += 30
        feedback.append("Freight line found with correct amount.")
    else:
        # Check partial
        any_freight, _ = find_line("Freight", -999999) # Check logic only
        if any_freight: # Found name but wrong amount
            score += 15 
            feedback.append("Freight line found but amount incorrect.")
        else:
            feedback.append("Freight line missing.")

    # Bank Fee Line (Charge: Bank Fee, Amount: 25) -> 30 pts
    found_fee, fee_amt = find_line("Bank", 25.00)
    if found_fee:
        score += 30
        feedback.append("Bank Fee line found with correct amount.")
    else:
        any_fee, _ = find_line("Bank", -999999)
        if any_fee:
            score += 15
            feedback.append("Bank Fee line found but amount incorrect.")
        else:
            feedback.append("Bank Fee line missing.")

    # Final tally
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }