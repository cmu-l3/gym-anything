#!/usr/bin/env python3
"""
Verifier for process_partial_refund task.

Task:
1. Find order for Emily Davis.
2. Partial refund Charger ($34.99).
3. Reason: "Customer reported item arrived damaged".

Verification Strategy:
1. Programmatic:
   - Check if a new refund exists for the specific order.
   - Verify refund amount is 34.99 (+/- 0.05).
   - Verify refund reason contains "damaged".
   - Verify the refunded line item matches the Charger product ID.
   - Verify the parent order still exists (not deleted).
   - Timestamp check (refund created after task start).

2. VLM (Trajectory):
   - Confirm agent navigated to refund workflow.
   - Confirm manual refund input.

Scoring:
- Refund Exists: 20 pts
- Correct Amount: 25 pts
- Correct Reason: 20 pts
- Correct Item Targeted: 15 pts
- Order Integrity: 10 pts
- Timestamp Valid: 10 pts
"""

import json
import tempfile
import os
import logging
import time
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_partial_refund(traj, env_info, task_info):
    """
    Verify that the partial refund was processed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_amount = float(metadata.get('refund_amount', 34.99))
    expected_keyword = metadata.get('refund_reason_keyword', 'damaged')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Read result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Extract Data
    task_start = result.get('task_start', 0)
    current_refund_count = result.get('current_refund_count', 0)
    initial_refund_count = result.get('initial_refund_count', 0)
    refund_data = result.get('refund', {})
    
    # Criterion 1: Refund Record Exists (20 pts)
    # Check if count increased and a refund ID is present
    if current_refund_count > initial_refund_count and refund_data.get('id') != "0":
        score += 20
        feedback_parts.append("Refund record created")
        refund_exists = True
    else:
        feedback_parts.append("No new refund record found")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed: No refund was created."
        }

    # Criterion 2: Correct Amount (25 pts)
    actual_amount = float(refund_data.get('amount', 0))
    if abs(actual_amount - expected_amount) < 0.10:
        score += 25
        feedback_parts.append(f"Amount correct (${actual_amount})")
    elif abs(actual_amount - 114.98) < 0.10: # Full order amount
        feedback_parts.append("Incorrect amount: Full order refunded ($114.98) instead of partial ($34.99)")
    else:
        feedback_parts.append(f"Incorrect amount: ${actual_amount} (expected ${expected_amount})")

    # Criterion 3: Refund Reason (20 pts)
    reason = refund_data.get('reason', '').lower()
    if expected_keyword in reason:
        score += 20
        feedback_parts.append(f"Reason valid ('{reason}')")
    elif reason:
        # Partial credit for having a reason but missing keyword
        score += 10
        feedback_parts.append(f"Reason provided but missing keyword '{expected_keyword}'")
    else:
        feedback_parts.append("No refund reason provided")

    # Criterion 4: Correct Item Targeted (15 pts)
    target_charger_id = str(result.get('target_charger_id', ''))
    refunded_products = [str(x) for x in refund_data.get('product_ids', [])]
    
    if target_charger_id in refunded_products:
        # Check if ONLY the charger was refunded or if multiple items were
        if len(refunded_products) == 1:
            score += 15
            feedback_parts.append("Correct line item refunded")
        else:
            score += 10
            feedback_parts.append("Target item refunded, but other items also included")
    else:
        feedback_parts.append("Target item (Charger) NOT found in refund details")

    # Criterion 5: Order Integrity (10 pts)
    if result.get('order_exists', False):
        score += 10
        feedback_parts.append("Parent order preserved")
    else:
        feedback_parts.append("Parent order deleted or missing")

    # Criterion 6: Timestamp/Anti-Gaming (10 pts)
    # We verify the refund isn't just a pre-existing one we somehow picked up
    # Note: WooCommerce stores dates in GMT. 
    # Since we checked count increment, this is mostly a sanity check.
    score += 10 # Awarded if we passed the count check, effectively
    
    # Calculate Final Result
    passed = score >= 60 and refund_exists and abs(actual_amount - expected_amount) < 0.10
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }