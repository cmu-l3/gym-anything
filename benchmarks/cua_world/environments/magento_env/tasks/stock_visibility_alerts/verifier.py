#!/usr/bin/env python3
"""Verifier for Stock Visibility & Alerts task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_stock_visibility_alerts(traj, env_info, task_info):
    """
    Verify configuration of stock visibility and alerts.

    Criteria:
    1. Display Out of Stock Products = Yes (1) [25 pts]
    2. Only X left Threshold = 5 [20 pts]
    3. Allow Stock Alerts = Yes (1) [20 pts]
    4. Allow Price Alerts = Yes (1) [20 pts]
    5. Stock Alert Email Sender = Customer Support (support) [15 pts]

    Pass threshold: 65 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        config = result.get('config', {})
        score = 0
        feedback_parts = []
        
        # 1. Verify Show Out of Stock (25 pts)
        val_oos = str(config.get('show_out_of_stock', '0')).strip()
        if val_oos == '1':
            score += 25
            feedback_parts.append("Out of Stock products visible (25 pts)")
        else:
            feedback_parts.append(f"Out of Stock visibility incorrect (value: {val_oos}, expected: 1)")

        # 2. Verify Threshold (20 pts)
        val_thresh = str(config.get('stock_threshold', '')).strip()
        # Handle potential float string "5.0000"
        try:
            thresh_float = float(val_thresh)
            if int(thresh_float) == 5:
                score += 20
                feedback_parts.append("Stock threshold set to 5 (20 pts)")
            else:
                feedback_parts.append(f"Stock threshold incorrect (value: {val_thresh}, expected: 5)")
        except ValueError:
             feedback_parts.append(f"Stock threshold not a valid number (value: {val_thresh})")

        # 3. Verify Stock Alerts (20 pts)
        val_stock_alert = str(config.get('allow_stock_alert', '0')).strip()
        if val_stock_alert == '1':
            score += 20
            feedback_parts.append("Stock alerts enabled (20 pts)")
        else:
            feedback_parts.append(f"Stock alerts disabled (value: {val_stock_alert})")

        # 4. Verify Price Alerts (20 pts)
        val_price_alert = str(config.get('allow_price_alert', '0')).strip()
        if val_price_alert == '1':
            score += 20
            feedback_parts.append("Price alerts enabled (20 pts)")
        else:
            feedback_parts.append(f"Price alerts disabled (value: {val_price_alert})")

        # 5. Verify Email Identity (15 pts)
        val_identity = str(config.get('stock_email_identity', '')).strip()
        if val_identity == 'support':
            score += 15
            feedback_parts.append("Email identity set to Customer Support (15 pts)")
        elif val_identity == 'general':
            feedback_parts.append("Email identity left as General Contact (expected Customer Support)")
        else:
            feedback_parts.append(f"Email identity incorrect (value: {val_identity})")

        passed = score >= 65
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }