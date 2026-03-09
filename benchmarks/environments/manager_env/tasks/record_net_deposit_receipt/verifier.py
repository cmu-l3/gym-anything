#!/usr/bin/env python3
"""
Verifier for record_net_deposit_receipt task.

Verifies:
1. A new receipt exists with total $485.00.
2. The receipt references Invoice #INV-STRIPE-001 (clearing the debt).
3. The receipt includes a deduction (negative line) for 'Bank Service Charges'.
4. Invoice is effectively paid (implied by 2).
"""

import json
import os
import sys
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_net_deposit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic result
    import tempfile
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
    
    # Criteria 1: Receipt Found with Correct Total (30 pts)
    if result.get('receipt_found', False) and result.get('receipt_total_correct', False):
        score += 30
        feedback.append("Receipt for $485.00 found.")
    else:
        feedback.append("No receipt with net total $485.00 found.")

    # Criteria 2: Receipt Links to Invoice (40 pts)
    # This implies the invoice was selected in the line item, clearing the debt.
    if result.get('receipt_links_invoice', False):
        score += 40
        feedback.append("Receipt correctly allocated to Invoice #INV-STRIPE-001.")
    else:
        feedback.append("Receipt does not reference the correct invoice.")

    # Criteria 3: Fee Expense Recorded (30 pts)
    if result.get('receipt_includes_fee', False):
        score += 30
        feedback.append("Bank Service Charges fee recorded correctly.")
    else:
        feedback.append("Fee deduction for Bank Service Charges not found in receipt.")

    # VLM Verification (Optional but robust) - Check if 'Paid in full' is visible in final state or trajectory
    # We use this as a sanity check or bonus confirmation
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        vlm_res = query_vlm(
            prompt="Is a receipt or invoice visible? Does it show a total of 485.00 or 'Paid in full'? Return JSON with boolean 'success'.",
            image=final_screenshot
        )
        if vlm_res.get('parsed', {}).get('success', False):
            # Could add bonus points or use as tie-breaker, but strictly relying on API data here for precision.
            pass

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }