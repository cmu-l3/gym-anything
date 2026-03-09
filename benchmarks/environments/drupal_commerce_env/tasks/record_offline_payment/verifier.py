#!/usr/bin/env python3
"""
Verifier for record_offline_payment task.

Scoring (100 points):
- Payment entity created for correct order (30 pts)
- Correct Amount (1392.00) (30 pts)
- Correct Gateway (manual/check) (10 pts)
- Payment Completed (15 pts)
- Order Balance Settled (15 pts)

Pass Threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_record_offline_payment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_amount = float(metadata.get('expected_amount', 1392.00))

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/record_offline_payment_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Payment Entity Created (30 pts)
    # Must be a NEW payment (count increased)
    new_payments = result.get('new_payments_count', 0)
    payment_found = result.get('payment_found', False)
    
    if payment_found and new_payments > 0:
        score += 30
        feedback_parts.append("New payment record found")
    elif payment_found:
        score += 10
        feedback_parts.append("Payment record found but count did not increase (modified existing?)")
    else:
        return {"passed": False, "score": 0, "feedback": "No payment record found for the order"}

    # 2. Correct Amount (30 pts)
    try:
        actual_amount = float(result.get('payment_amount', 0))
        if abs(actual_amount - expected_amount) < 0.01:
            score += 30
            feedback_parts.append(f"Amount correct (${actual_amount})")
        else:
            feedback_parts.append(f"Incorrect amount: ${actual_amount} (expected ${expected_amount})")
    except ValueError:
        feedback_parts.append("Invalid payment amount format")

    # 3. Correct Gateway (10 pts)
    gateway = result.get('payment_gateway', '')
    if gateway == 'manual':
        score += 10
        feedback_parts.append("Correct gateway (manual)")
    else:
        feedback_parts.append(f"Wrong gateway: {gateway}")

    # 4. Payment Completed (15 pts)
    state = result.get('payment_state', '')
    if state == 'completed':
        score += 15
        feedback_parts.append("Payment state is completed")
    else:
        feedback_parts.append(f"Payment state is '{state}' (expected 'completed')")

    # 5. Order Balance Settled (15 pts)
    # Check if total_paid matches total_price
    try:
        total_paid = float(result.get('order_total_paid', 0))
        total_price = float(result.get('order_total_price', 0))
        
        # If order total price is 0, something is wrong with setup or order retrieval
        if total_price > 0 and abs(total_paid - total_price) < 0.01:
            score += 15
            feedback_parts.append("Order balance fully settled")
        elif total_price > 0:
            feedback_parts.append(f"Order not fully paid ({total_paid}/{total_price})")
    except ValueError:
        pass

    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }