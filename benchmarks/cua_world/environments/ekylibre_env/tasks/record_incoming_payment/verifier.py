#!/usr/bin/env python3
"""
Verifier for record_incoming_payment task.
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_record_incoming_payment(traj, env_info, task_info):
    """
    Verify that the incoming payment was recorded correctly in the database.
    
    Criteria:
    1. Payment record exists (20 pts)
    2. Correct Amount: 8750.00 (25 pts)
    3. Correct Payer: Coopérative Agricole de Charente (20 pts)
    4. Correct Date: 2024-09-15 (15 pts)
    5. Correct Reference: CHQ-4721-2024 (10 pts)
    6. Anti-gaming: Created after task start (10 pts)
    """
    
    # 1. Get copy_from_env function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    
    # 2. Retrieve result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 3. Extract data
    payment_found = result.get('payment_found', False)
    details = result.get('payment_details', {})
    counts = result.get('counts', {})
    task_start = result.get('task_start_timestamp', 0)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Metadata for expected values
    metadata = task_info.get('metadata', {})
    exp_amount = metadata.get('expected_amount', 8750.00)
    exp_date = metadata.get('expected_date', '2024-09-15')
    exp_ref = metadata.get('expected_reference', 'CHQ-4721-2024')
    exp_payer = metadata.get('expected_payer', 'Coopérative Agricole de Charente')

    # CRITERION 1: Record Count Increased / Payment Found (20 pts)
    initial_count = counts.get('initial', 0)
    final_count = counts.get('final', 0)
    
    if payment_found:
        score += 20
        feedback_parts.append("Payment record found in database")
    elif final_count > initial_count:
        score += 10
        feedback_parts.append(f"Payment count increased ({initial_count} -> {final_count}), but specific record match failed")
    else:
        return {"passed": False, "score": 0, "feedback": "No new payment records found."}

    # If payment found, check details
    if payment_found:
        # CRITERION 2: Amount (25 pts)
        try:
            amount = float(details.get('amount', 0))
            if abs(amount - exp_amount) < 0.01:
                score += 25
                feedback_parts.append(f"Correct amount ({amount})")
            else:
                feedback_parts.append(f"Incorrect amount: expected {exp_amount}, got {amount}")
        except ValueError:
            feedback_parts.append("Invalid amount format")

        # CRITERION 3: Payer (20 pts)
        payer = details.get('payer', '')
        if "Coop" in payer and "Charente" in payer:
            score += 20
            feedback_parts.append(f"Correct payer ({payer})")
        else:
            feedback_parts.append(f"Incorrect payer: expected '{exp_payer}', got '{payer}'")

        # CRITERION 4: Date (15 pts)
        date_str = details.get('date', '')
        # Handle potential variations in date format if necessary, though SQL usually standard YYYY-MM-DD
        if date_str == exp_date:
            score += 15
            feedback_parts.append(f"Correct date ({date_str})")
        else:
            feedback_parts.append(f"Incorrect date: expected {exp_date}, got {date_str}")

        # CRITERION 5: Reference (10 pts)
        ref = details.get('reference', '')
        if ref == exp_ref:
            score += 10
            feedback_parts.append(f"Correct reference ({ref})")
        elif exp_ref in ref: # Partial match
            score += 5
            feedback_parts.append(f"Reference partial match ('{ref}')")
        else:
            feedback_parts.append(f"Incorrect reference: expected {exp_ref}, got '{ref}'")

        # CRITERION 6: Anti-Gaming / Timestamp (10 pts)
        created_ts = details.get('created_timestamp', 0)
        try:
            created_ts = int(created_ts)
            task_start = int(task_start)
            if created_ts > task_start:
                score += 10
                feedback_parts.append("Record created during task session")
            else:
                feedback_parts.append("Warning: Record timestamp predates task start")
        except:
            feedback_parts.append("Could not verify timestamp")

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }