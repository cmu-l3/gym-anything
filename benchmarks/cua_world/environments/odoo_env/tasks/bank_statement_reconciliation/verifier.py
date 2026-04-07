#!/usr/bin/env python3
"""
Verifier for bank_statement_reconciliation task.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_bank_statement_reconciliation(traj, env_info, task_info):
    """
    Verify that 4 specific invoices/bills were reconciled and a bank fee was recorded.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env('/tmp/task_result.json', temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result.get('error')}"}

    score = 0
    feedback_parts = []
    
    docs = result.get('documents', {})
    
    # Check Invoice 1 (Alpine Ridge)
    inv1 = docs.get('invoice_1', {})
    if inv1.get('state') in ['paid', 'in_payment']:
        score += 15
        feedback_parts.append("Alpine Ridge Invoice Paid (15/15)")
    else:
        feedback_parts.append("Alpine Ridge Invoice NOT Paid (0/15)")

    # Check Invoice 2 (Coastal Bay)
    inv2 = docs.get('invoice_2', {})
    if inv2.get('state') in ['paid', 'in_payment']:
        score += 15
        feedback_parts.append("Coastal Bay Invoice Paid (15/15)")
    else:
        feedback_parts.append("Coastal Bay Invoice NOT Paid (0/15)")

    # Check Bill 1 (Summit Supply)
    bill1 = docs.get('bill_1', {})
    if bill1.get('state') in ['paid', 'in_payment']:
        score += 15
        feedback_parts.append("Summit Supply Bill Paid (15/15)")
    else:
        feedback_parts.append("Summit Supply Bill NOT Paid (0/15)")

    # Check Bill 2 (Pacific Materials)
    bill2 = docs.get('bill_2', {})
    if bill2.get('state') in ['paid', 'in_payment']:
        score += 15
        feedback_parts.append("Pacific Materials Bill Paid (15/15)")
    else:
        feedback_parts.append("Pacific Materials Bill NOT Paid (0/15)")

    # Check Bank Fee
    if result.get('bank_fee_found'):
        score += 20
        feedback_parts.append("Bank Fee Recorded (20/20)")
    else:
        feedback_parts.append("Bank Fee NOT found (0/20)")

    # Check Statement Existence
    if result.get('statements_found'):
        score += 20
        feedback_parts.append("Bank Statement Created (20/20)")
    else:
        feedback_parts.append("No Bank Statement found (0/20)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }