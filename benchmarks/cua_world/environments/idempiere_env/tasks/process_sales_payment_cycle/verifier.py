#!/usr/bin/env python3
"""
Verifier for process_sales_payment_cycle task.
Verifies:
1. AR Invoice created for Joe Block (5 Oak Trees).
2. AR Receipt created for Joe Block (Matching Amount).
3. Payment explicitly allocated to Invoice (Critical Step).
4. Invoice status is 'Paid'.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_sales_payment_cycle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Evaluate Invoice (Max 30 pts)
    invoice = result.get('invoice_data', {}) or {}
    inv_created = False
    inv_amount = 0
    
    if invoice:
        inv_created = True
        score += 10
        feedback.append("Invoice created")
        
        # Check Content
        if invoice.get('correct_lines', 0) > 0:
            score += 10
            feedback.append("Invoice contains 5 Oak Trees")
        else:
            feedback.append("Invoice missing correct product/qty")
            
        # Check Status
        docstatus = invoice.get('docstatus', '??')
        if docstatus in ['CO', 'CL']:
            score += 10
            feedback.append("Invoice Completed")
        else:
            feedback.append(f"Invoice not completed (Status: {docstatus})")
            
        inv_amount = float(invoice.get('grandtotal', 0))
    else:
        feedback.append("No valid invoice found")

    # 3. Evaluate Payment (Max 20 pts)
    payment = result.get('payment_data', {}) or {}
    pay_created = False
    
    if payment:
        pay_created = True
        score += 10
        feedback.append("Payment created")
        
        pay_amount = float(payment.get('payamt', 0))
        # Allow small floating point diff
        if abs(pay_amount - inv_amount) < 0.01 and inv_amount > 0:
            score += 10
            feedback.append("Payment amount matches Invoice")
        else:
            feedback.append(f"Payment amount ({pay_amount}) mismatch with Invoice ({inv_amount})")
    else:
        feedback.append("No valid payment found")

    # 4. Evaluate Allocation & Paid Status (Max 50 pts)
    # This is the "Cycle" part
    allocation_found = result.get('allocation_found', False)
    is_paid = invoice.get('ispaid', 'N') == 'Y'
    
    if allocation_found:
        score += 30
        feedback.append("Payment explicitly allocated to Invoice")
    else:
        feedback.append("Payment NOT allocated to Invoice")
        
    if is_paid:
        score += 20
        feedback.append("Invoice marked as PAID")
    elif inv_created:
        feedback.append("Invoice remains UNPAID")

    # 5. VLM Verification (Bonus/Confirmation)
    # If allocation failed via DB, check if they tried via UI
    if not allocation_found and query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        vlm_resp = query_vlm(
            images=frames + [final],
            prompt="Did the user open the 'Payment Allocation' or 'View Allocation' window and try to process an allocation? Look for a grid showing invoices and payments being selected."
        )
        if vlm_resp.get('parsed', {}).get('answer', False) is True:
             # Giving partial credit for attempting the difficult step
             score += 10
             feedback.append("(VLM) User attempted allocation but didn't complete it")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }