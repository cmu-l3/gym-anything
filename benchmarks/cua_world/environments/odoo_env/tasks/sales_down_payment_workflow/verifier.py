#!/usr/bin/env python3
"""
Verifier for sales_down_payment_workflow task.

Scoring (100 points total):
1. Sales Order Confirmed with correct product: 20 pts
2. Down Payment Invoice created (approx $1260): 25 pts
3. Down Payment Invoice Paid: 20 pts
4. Final Invoice created (deducting DP): 20 pts
5. Final Invoice Posted: 15 pts

Pass threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_sales_down_payment_workflow(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    
    try:
        copy_from_env('/tmp/sales_down_payment_result.json', temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Check 1: SO Found and Confirmed (20 pts)
    so_data = result.get('so_data', {})
    if result.get('so_found') and so_data.get('correct_product_line'):
        if so_data.get('state') in ['sale', 'done']:
            score += 20
            feedback_parts.append("Sales Order confirmed (20/20)")
        else:
            feedback_parts.append("Sales Order created but not confirmed (0/20)")
    else:
        feedback_parts.append("Sales Order not found or incorrect product (0/20)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Analyze Invoices
    invoices = result.get('invoices', [])
    target_price = result.get('setup_target_price', 4200)
    expected_dp = target_price * 0.30 # 1260
    
    dp_invoice_found = False
    dp_paid = False
    final_invoice_found = False
    final_posted = False

    for inv in invoices:
        amount = inv.get('amount_total', 0)
        is_dp = inv.get('is_down_payment')
        has_neg = inv.get('has_negative_line')
        state = inv.get('state')
        pay_state = inv.get('payment_state')

        # Check for Down Payment Invoice
        # Logic: Amount is roughly 1260 OR explicitly marked as DP
        if abs(amount - expected_dp) < 50 or (is_dp and not has_neg):
            dp_invoice_found = True
            if pay_state in ['paid', 'in_payment']:
                dp_paid = True
        
        # Check for Final Invoice
        # Logic: Has a negative line (deducting DP) OR amount is residual (Total - DP)
        # Note: In Odoo standard flow, final invoice includes the product line + negative DP line.
        # The total amount should be roughly Total - DP (~2940).
        residual = target_price - expected_dp
        if has_neg or abs(amount - residual) < 50:
            # Distinguish from the DP invoice itself (which is ~1260)
            if abs(amount - expected_dp) > 10: 
                final_invoice_found = True
                if state == 'posted':
                    final_posted = True

    # Check 2: DP Invoice Created (25 pts)
    if dp_invoice_found:
        score += 25
        feedback_parts.append("Down Payment invoice created (25/25)")
    else:
        feedback_parts.append("Down Payment invoice missing (0/25)")

    # Check 3: DP Paid (20 pts)
    if dp_paid:
        score += 20
        feedback_parts.append("Down Payment marked as paid (20/20)")
    else:
        feedback_parts.append("Down Payment not paid (0/20)")

    # Check 4: Final Invoice Created (20 pts)
    if final_invoice_found:
        score += 20
        feedback_parts.append("Final invoice created (20/20)")
    else:
        feedback_parts.append("Final invoice missing (0/20)")

    # Check 5: Final Invoice Posted (15 pts)
    if final_posted:
        score += 15
        feedback_parts.append("Final invoice posted (15/15)")
    else:
        feedback_parts.append("Final invoice not posted (0/15)")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }