#!/usr/bin/env python3
"""
Verifier for Modify Order Items task.

Criteria:
1. Target Order modified during task (15 pts)
2. Old item (Organic Cotton T-Shirt) removed (25 pts)
3. New item (Merino Wool Sweater) added (25 pts)
4. New item quantity is 1 (10 pts)
5. Order totals recalculated (25 pts) - Verified by checking total price change

Anti-gaming:
- Checks post_modified timestamp against task start time.
- Verifies specific items, not just any modification.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modify_order_items(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Modification Check (15 pts)
    if result.get('was_modified_during_task', False):
        score += 15
        feedback.append("Order modified successfully.")
    else:
        feedback.append("Order was not modified (timestamp unchanged).")

    # 2. Item Removal (25 pts)
    if not result.get('has_tshirt', True):
        score += 25
        feedback.append("Original item removed.")
    else:
        feedback.append("Original item (T-Shirt) still present.")

    # 3. Item Addition (25 pts)
    if result.get('has_sweater', False):
        score += 25
        feedback.append("New item added.")
    else:
        feedback.append("New item (Sweater) not found.")

    # 4. Quantity Check (10 pts)
    try:
        qty = float(result.get('sweater_qty', 0))
        if qty == 1.0:
            score += 10
            feedback.append("Correct quantity.")
        else:
            feedback.append(f"Incorrect quantity: {qty}")
    except:
        feedback.append("Could not verify quantity.")

    # 5. Total Recalculation Check (25 pts)
    # T-Shirt was ~24.99, Sweater is ~89.99. 
    # If total matches initial, they didn't recalculate or didn't swap.
    # If total is significantly higher, they likely recalculated.
    try:
        initial = float(result.get('initial_total', 0))
        current = float(result.get('current_total', 0))
        
        # We expect the price to increase significantly
        # 89.99 - 24.99 = 65.00 diff
        if current > (initial + 40.0): 
            score += 25
            feedback.append("Order totals recalculated correctly.")
        elif current == initial:
            feedback.append("Order total unchanged - did you click Recalculate?")
        else:
            # If they just removed the shirt, price would drop.
            # If they added sweater but didn't remove shirt, price would be much higher.
            # We assume Recalculate was clicked if the price changed meaningfully towards the target.
            # Let's be generous: if it changed and items are correct, they likely recalculated.
            if result.get('has_sweater') and not result.get('has_tshirt') and current != initial:
                score += 25
                feedback.append("Order totals updated.")
            else:
                feedback.append(f"Order total dubious (Initial: {initial}, Current: {current})")
    except:
        feedback.append("Could not verify totals.")

    return {
        "passed": score >= 85,
        "score": score,
        "feedback": " ".join(feedback)
    }