#!/usr/bin/env python3
"""
Verifier for prepare_payment_batch task.

Verifies:
1. Agent created a Vendor Invoice for Joe Block ($150).
2. Invoice is Completed (CO).
3. Agent created a Payment Selection batch.
4. Payment Selection uses the correct Bank Account.
5. CRITICAL: Payment Selection contains a line referencing the created invoice.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prepare_payment_batch(traj, env_info, task_info):
    """
    Verify the Payment Batch creation workflow.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    # Scoring Variables
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Extract data
    invoice_found = result.get('invoice_found', False)
    invoice_status = result.get('invoice_status', '')
    paysel_found = result.get('payment_selection_found', False)
    bank_name = result.get('bank_account_name', '')
    linkage_found = result.get('linkage_found', False)

    # Criterion 1: Invoice Creation (20 pts)
    if invoice_found:
        score += 20
        feedback_parts.append("Vendor Invoice created successfully")
    else:
        feedback_parts.append("Failed to create the specific Vendor Invoice ($150 for Joe Block)")

    # Criterion 2: Invoice Status (20 pts)
    # Status 'CO' is Completed, 'CL' is Closed (also valid). 'DR' is Draft (fail).
    if invoice_found:
        if invoice_status in ['CO', 'CL']:
            score += 20
            feedback_parts.append("Invoice is Completed")
        else:
            feedback_parts.append(f"Invoice status is '{invoice_status}' (expected 'Completed')")

    # Criterion 3: Payment Selection Header (20 pts)
    if paysel_found:
        score += 20
        feedback_parts.append("Payment Selection batch created")
    else:
        feedback_parts.append("No Payment Selection batch found")

    # Criterion 4: Bank Account (10 pts)
    # Expecting 'HQ Checking' or similar. Verification script returns the name.
    if paysel_found:
        if 'Checking' in bank_name:
            score += 10
            feedback_parts.append(f"Correct Bank Account used ({bank_name})")
        else:
            feedback_parts.append(f"Incorrect Bank Account ({bank_name})")

    # Criterion 5: Linkage (30 pts)
    # This is the most critical part proving the workflow was connected.
    if linkage_found:
        score += 30
        feedback_parts.append("Invoice successfully included in Payment Batch")
    else:
        feedback_parts.append("Invoice NOT found in the Payment Batch lines")

    # Final Evaluation
    passed = (score >= 70) and linkage_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }