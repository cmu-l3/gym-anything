#!/usr/bin/env python3
"""Verifier for Sales Email Copy Config task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sales_email_copy_config(traj, env_info, task_info):
    """
    Verify Sales Email configuration.

    Criteria:
    1. Order Copy Recipient is 'manager@nesthome.com' (25 pts)
    2. Order Copy Method is 'bcc' (25 pts)
    3. Invoice Copy Recipient is 'accounting@nesthome.com' (25 pts)
    4. Invoice Copy Method is 'copy' (Separate Email) (25 pts)

    Pass threshold: 100 pts (Exact configuration required)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    exp_order_recip = metadata.get('expected_order_recipient', 'manager@nesthome.com')
    exp_order_method = metadata.get('expected_order_method', 'bcc')
    exp_invoice_recip = metadata.get('expected_invoice_recipient', 'accounting@nesthome.com')
    exp_invoice_method = metadata.get('expected_invoice_method', 'copy')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/sales_email_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. Check Order Recipient
        act_order_recip = str(result.get('order_copy_to', '')).strip()
        if act_order_recip == exp_order_recip:
            score += 25
            feedback_parts.append("Order copy recipient correct")
        else:
            feedback_parts.append(f"Order recipient incorrect: expected '{exp_order_recip}', got '{act_order_recip}'")

        # 2. Check Order Method
        act_order_method = str(result.get('order_copy_method', '')).strip()
        if act_order_method == exp_order_method:
            score += 25
            feedback_parts.append("Order copy method correct (BCC)")
        else:
            feedback_parts.append(f"Order copy method incorrect: expected '{exp_order_method}', got '{act_order_method}'")

        # 3. Check Invoice Recipient
        act_invoice_recip = str(result.get('invoice_copy_to', '')).strip()
        if act_invoice_recip == exp_invoice_recip:
            score += 25
            feedback_parts.append("Invoice copy recipient correct")
        else:
            feedback_parts.append(f"Invoice recipient incorrect: expected '{exp_invoice_recip}', got '{act_invoice_recip}'")

        # 4. Check Invoice Method
        act_invoice_method = str(result.get('invoice_copy_method', '')).strip()
        # 'copy' is the database value for "Separate Email"
        if act_invoice_method == exp_invoice_method:
            score += 25
            feedback_parts.append("Invoice copy method correct (Separate Email)")
        else:
            feedback_parts.append(f"Invoice copy method incorrect: expected '{exp_invoice_method}' (Separate Email), got '{act_invoice_method}'")

        # Final Evaluation
        passed = (score == 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed due to system error: {str(e)}"
        }