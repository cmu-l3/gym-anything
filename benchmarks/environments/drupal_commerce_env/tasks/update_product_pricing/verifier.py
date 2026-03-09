#!/usr/bin/env python3
"""
Verifier for update_product_pricing task.
"""

import json
import logging
import os
import tempfile
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_product_pricing(traj, env_info, task_info):
    """
    Verify pricing updates and product status changes.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    sony_target = float(metadata.get('sony_target_price', 329.99))
    logi_target = float(metadata.get('logi_target_price', 79.99))
    bose_target_status = int(metadata.get('bose_target_status', 0)) # 0 = Unpublished
    bose_original_price = float(metadata.get('bose_target_price_unchanged', 329.00))

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result file: {e}"}

    score = 0
    feedback = []
    
    initial_state = result.get("initial_state", {})
    task_start = int(result.get("task_start_time", 0))

    # Helper for loose float comparison
    def is_close(a, b, tol=0.02):
        try:
            return abs(float(a) - float(b)) < tol
        except:
            return False

    # 1. Verify Sony Price (25 pts)
    sony_price = result.get("sony_price")
    sony_changed = int(result.get("sony_changed_timestamp", 0))
    
    if is_close(sony_price, sony_target):
        # Anti-gaming: check if it actually changed from initial
        if is_close(sony_price, initial_state.get("sony_price", 0)):
             feedback.append("Sony price is correct but matches initial state (no change detected).")
        else:
            score += 25
            feedback.append(f"Sony price updated to ${sony_price}.")
    else:
        feedback.append(f"Sony price incorrect. Expected ${sony_target}, got ${sony_price}.")

    # 2. Verify Logitech Price (25 pts)
    logi_price = result.get("logi_price")
    
    if is_close(logi_price, logi_target):
        if is_close(logi_price, initial_state.get("logi_price", 0)):
             feedback.append("Logitech price is correct but matches initial state.")
        else:
            score += 25
            feedback.append(f"Logitech price updated to ${logi_price}.")
    else:
        feedback.append(f"Logitech price incorrect. Expected ${logi_target}, got ${logi_price}.")

    # 3. Verify Bose Status (25 pts)
    bose_status = int(result.get("bose_status", -1))
    
    if bose_status == bose_target_status:
        score += 25
        feedback.append("Bose product successfully unpublished.")
    else:
        feedback.append(f"Bose status incorrect. Expected {bose_target_status} (unpublished), got {bose_status}.")

    # 4. Verify Bose Price Unchanged (10 pts)
    # The task asked to unpublish, NOT change price. 
    bose_price = result.get("bose_price")
    if is_close(bose_price, bose_original_price):
        score += 10
        feedback.append("Bose price correctly left unchanged.")
    else:
        feedback.append(f"Bose price was accidentally changed to ${bose_price}.")

    # 5. Verify No Collateral Damage (15 pts)
    # We expect exactly one product to disappear from published list (Bose)
    # Initial published count - 1 should equal current published count
    initial_pub = int(initial_state.get("total_published", 0))
    current_pub = int(result.get("total_published", 0))
    
    expected_pub = initial_pub - 1
    if current_pub == expected_pub:
        score += 15
        feedback.append("Product counts match expected changes (no collateral deletion).")
    else:
        feedback.append(f"Unexpected change in published product count. Started with {initial_pub}, expected {expected_pub}, found {current_pub}.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }