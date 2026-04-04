#!/usr/bin/env python3
"""
Verifier for Configure Bundle Promotion task.
Scores based on existence, status, offer type, discount amount, and targeting logic.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_bundle_promotion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    trigger_sku = metadata.get('trigger_sku', 'DJI-MINI3')
    target_sku = metadata.get('target_sku', 'ANKER-PC26800')

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

    data = result.get('promotion_data', {})
    if not data.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Promotion 'Drone Power Bundle' was not found."
        }

    score = 0
    feedback = []

    # 1. Promotion Exists & Active (20 pts)
    if data.get('found'):
        if data.get('status'):
            score += 20
            feedback.append("Promotion exists and is active.")
        else:
            score += 10
            feedback.append("Promotion exists but is disabled.")
    
    # 2. Correct Offer Type (20 pts)
    # Expecting 'order_item_percentage_off' (per item), NOT 'order_percentage_off' (whole order)
    offer_type = data.get('offer_type', '')
    if 'order_item_percentage_off' in offer_type:
        score += 20
        feedback.append("Correct offer type (Item Percentage Off).")
    elif 'percentage_off' in offer_type:
        score += 5
        feedback.append(f"Wrong offer scope. Type is '{offer_type}', expected 'order_item_percentage_off'.")
    else:
        feedback.append(f"Incorrect offer type: {offer_type}")

    # 3. Discount Amount (10 pts)
    amount = data.get('offer_amount', 0.0)
    if 0.49 <= amount <= 0.51:
        score += 10
        feedback.append("Correct discount amount (50%).")
    else:
        feedback.append(f"Incorrect discount amount: {amount} (Expected 0.50)")

    # 4. Trigger Condition (Order must contain Drone) (25 pts)
    trigger_skus = data.get('condition_trigger_skus', [])
    # Check if trigger_sku is in the list
    if any(trigger_sku in sku for sku in trigger_skus):
        score += 25
        feedback.append(f"Correct trigger condition (Requires {trigger_sku}).")
    else:
        feedback.append(f"Missing trigger condition: Order must contain {trigger_sku}.")

    # 5. Target Condition (Discount applies to Anker PowerCore) (25 pts)
    target_skus = data.get('offer_target_skus', [])
    if any(target_sku in sku for sku in target_skus):
        score += 25
        feedback.append(f"Correct target condition (Discount applies to {target_sku}).")
    else:
        feedback.append(f"Missing target configuration: Discount should restrict to {target_sku}.")

    # Anti-gaming: Check timestamp
    created_time = data.get('created_time', 0)
    task_start = result.get('task_start_timestamp', 0)
    if created_time < task_start:
        score = 0
        feedback.append("Anti-gaming: Promotion appears to have been created before task started.")

    passed = score >= 85
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }