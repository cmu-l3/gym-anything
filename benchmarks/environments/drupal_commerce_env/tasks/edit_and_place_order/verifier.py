#!/usr/bin/env python3
"""
Verifier for edit_and_place_order task.
Scores based on DB state of the specific order ID tracked from setup.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_edit_and_place_order(traj, env_info, task_info):
    """
    Verify the agent edited the correct draft order, added the product,
    updated the address, and placed the order.
    """
    # 1. Boilerplate to read result file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    original_sku = metadata.get('original_sku', 'SONY-WH1000XM5')
    added_sku = metadata.get('added_sku', 'LOGI-MXM3S')
    expected_city = metadata.get('expected_city', 'Chicago')
    expected_state = metadata.get('expected_state', 'IL')
    expected_zip = metadata.get('expected_zip', '60601')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # 2. Extract Data
    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Setup error: {result['error']}"}

    order_state = result.get("order_state", "draft")
    skus = [s.strip().upper() for s in result.get("skus", [])]
    billing = result.get("billing", {})
    modified = result.get("modified_during_task", False)

    score = 0
    feedback = []

    # Criterion 1: Activity check (anti-gaming) (0 pts but prerequisite)
    if not modified and order_state == "draft":
        return {"passed": False, "score": 0, "feedback": "Order was not modified during the task."}

    # Criterion 2: Original item preserved (10 pts)
    # The original item (Sony) should still be there.
    if original_sku in skus:
        score += 10
        feedback.append(f"Original item ({original_sku}) preserved.")
    else:
        feedback.append(f"Original item ({original_sku}) missing from order.")

    # Criterion 3: New item added (25 pts)
    if added_sku in skus:
        score += 25
        feedback.append(f"New item ({added_sku}) added successfully.")
    else:
        feedback.append(f"New item ({added_sku}) not found in order.")

    # Criterion 4: Billing Address Updated (35 pts total)
    # City (15)
    actual_city = billing.get("locality", "")
    if actual_city.lower() == expected_city.lower():
        score += 15
        feedback.append(f"City matched ({expected_city}).")
    else:
        feedback.append(f"City mismatch: expected {expected_city}, got {actual_city}.")

    # State (10)
    actual_state = billing.get("administrative_area", "")
    if actual_state.upper() == expected_state.upper():
        score += 10
        feedback.append(f"State matched ({expected_state}).")
    else:
        feedback.append(f"State mismatch: expected {expected_state}, got {actual_state}.")

    # Zip (10)
    actual_zip = billing.get("postal_code", "")
    if str(actual_zip).strip() == str(expected_zip).strip():
        score += 10
        feedback.append(f"Zip matched ({expected_zip}).")
    else:
        feedback.append(f"Zip mismatch: expected {expected_zip}, got {actual_zip}.")

    # Criterion 5: Order Placed (30 pts)
    # State should NOT be 'draft'
    if order_state and order_state != 'draft':
        score += 30
        feedback.append(f"Order placed successfully (State: {order_state}).")
    else:
        feedback.append(f"Order still in '{order_state}' state (expected placed/completed).")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }