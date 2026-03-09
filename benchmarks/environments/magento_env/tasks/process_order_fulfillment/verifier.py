#!/usr/bin/env python3
"""
Verifier for Process Order Fulfillment task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_order_fulfillment(traj, env_info, task_info):
    """
    Verify that order #000000001 was invoiced and shipped with tracking.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_track = metadata.get('expected_tracking_number', '1Z999AA10123456784')
    expected_title = metadata.get('expected_carrier_title', 'UPS')

    # Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/process_order_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Invoice Verification (35 pts total)
    invoice = result.get('invoice', {})
    if invoice.get('exists'):
        # Check if state is Paid (2)
        # Magento Invoice States: 1=Open, 2=Paid, 3=Canceled
        if str(invoice.get('state')) == '2':
            score += 25
            feedback_parts.append("Invoice created and paid (25 pts)")
        else:
            score += 15
            feedback_parts.append("Invoice created but not in 'Paid' state (15 pts)")
            
        # Check total > 0 (sanity check)
        try:
            if float(invoice.get('total', 0)) > 0:
                score += 10
                feedback_parts.append("Invoice has valid amount (10 pts)")
        except:
            pass
    else:
        feedback_parts.append("No invoice found for order #000000001")

    # 2. Shipment Verification (50 pts total)
    shipment = result.get('shipment', {})
    if shipment.get('exists'):
        score += 25
        feedback_parts.append("Shipment created (25 pts)")
        
        # Check Tracking Number
        actual_track = str(shipment.get('tracking_number', '')).strip()
        if actual_track == expected_track:
            score += 20
            feedback_parts.append(f"Tracking number correct: {expected_track} (20 pts)")
        else:
            feedback_parts.append(f"Tracking number mismatch: expected '{expected_track}', got '{actual_track}'")
            
        # Check Tracking Title
        actual_title = str(shipment.get('tracking_title', '')).strip()
        if expected_title.lower() in actual_title.lower():
            score += 5
            feedback_parts.append(f"Tracking title matches '{expected_title}' (5 pts)")
        else:
            feedback_parts.append(f"Tracking title mismatch: expected '{expected_title}', got '{actual_title}'")
    else:
        feedback_parts.append("No shipment found for order #000000001")

    # 3. Order Status Verification (15 pts)
    # Status 'complete' happens automatically if Invoiced + Shipped
    order_status = str(result.get('order_status', '')).lower()
    if order_status == 'complete':
        score += 15
        feedback_parts.append("Order status is 'complete' (15 pts)")
    else:
        feedback_parts.append(f"Order status is '{order_status}' (expected 'complete')")

    # Anti-gaming check: New records must have been created
    counts = result.get('counts', {})
    if counts.get('current_invoices', 0) <= counts.get('initial_invoices', 0):
        if invoice.get('exists'):
             feedback_parts.append("WARNING: Invoice count did not increase (reused old invoice?)")
    
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }