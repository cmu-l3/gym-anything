#!/usr/bin/env python3
"""
Verifier for record_payment_with_withholding task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_payment_with_withholding(traj, env_info, task_info):
    """
    Verify that the payment was recorded correctly with withholding tax.
    
    Criteria:
    1. Invoice is fully paid (Balance 0) - 40 pts
    2. Cash on Hand increased by 900 - 30 pts
    3. Withholding Tax Receivable increased by 100 - 30 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    data = result.get('scraped_data', {})
    score = 0
    feedback_parts = []
    
    # 1. Check Invoice Status (40 pts)
    invoice_paid = data.get('invoice_paid', False)
    invoice_balance = data.get('invoice_balance', 1000.0)
    
    if invoice_paid or invoice_balance == 0.0:
        score += 40
        feedback_parts.append("Invoice is fully paid.")
    else:
        feedback_parts.append(f"Invoice still has balance: {invoice_balance}")

    # 2. Check Cash Increase (30 pts)
    # Expected: 900.00
    cash_increase = data.get('cash_increase', 0.0)
    if 899.0 <= cash_increase <= 901.0:
        score += 30
        feedback_parts.append("Cash recorded correctly (900.00).")
    elif cash_increase > 0:
        feedback_parts.append(f"Cash increased by {cash_increase}, expected 900.00.")
    else:
        feedback_parts.append("Cash on Hand did not increase.")

    # 3. Check Tax Asset (30 pts)
    # Expected: 100.00
    tax_increase = data.get('tax_asset_increase', 0.0)
    if 99.0 <= tax_increase <= 101.0:
        score += 30
        feedback_parts.append("Withholding tax recorded correctly (100.00).")
    elif tax_increase > 0:
        feedback_parts.append(f"Tax asset increased by {tax_increase}, expected 100.00.")
    else:
        feedback_parts.append("Withholding Tax Receivable not used correctly.")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }