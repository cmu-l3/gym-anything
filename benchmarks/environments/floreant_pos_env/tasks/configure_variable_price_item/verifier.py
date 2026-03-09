#!/usr/bin/env python3
"""
Verifier for configure_variable_price_item task.

Checks:
1. 'Fresh Catch' item exists in database.
2. 'Fresh Catch' item Base Price is NOT 42.50 (Anti-gaming: must be variable).
3. A Ticket Item exists for 'Fresh Catch' with price 42.50.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_variable_price_item(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    db_data = result.get("db_data", {})
    menu_items = db_data.get("menu_items", [])
    ticket_items = db_data.get("ticket_items", [])
    
    feedback = []
    score = 0
    
    # -------------------------------------------------------
    # CRITERION 1: Menu Item Created (20 pts)
    # -------------------------------------------------------
    fresh_catch_def = next((i for i in menu_items if "Fresh Catch" in i.get("name", "")), None)
    
    if fresh_catch_def:
        score += 20
        feedback.append("Menu item 'Fresh Catch' created.")
    else:
        feedback.append("Menu item 'Fresh Catch' NOT found in database.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # -------------------------------------------------------
    # CRITERION 2: Configuration (Variable Price) (30 pts)
    # -------------------------------------------------------
    # The base price in the DB should NOT be the test price (42.50).
    # If the base price is 42.50, they likely just hardcoded a fixed price item.
    # Typically variable price items have 0.0 or empty price in DB.
    
    base_price = fresh_catch_def.get("price", 0.0)
    target_price = 42.50
    
    if abs(base_price - target_price) > 0.01:
        score += 30
        feedback.append(f"Item configuration correct (Base price ${base_price} != ${target_price}).")
    else:
        feedback.append(f"Anti-Gaming Fail: Item base price is set to ${base_price}. It should be variable (0.0), not hardcoded to the test value.")
        # We don't fail immediately, but they lose these points

    # -------------------------------------------------------
    # CRITERION 3: Order Processed (20 pts)
    # -------------------------------------------------------
    sold_items = [t for t in ticket_items if "Fresh Catch" in t.get("name", "")]
    
    if sold_items:
        score += 20
        feedback.append("Order ticket found containing 'Fresh Catch'.")
    else:
        feedback.append("No order ticket found for 'Fresh Catch'.")
        # Fail here if no order placed
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # -------------------------------------------------------
    # CRITERION 4: Price Entry Accuracy (30 pts)
    # -------------------------------------------------------
    # Check if ANY of the sold items has the correct manual price
    correct_price_sale = False
    for item in sold_items:
        # Check both item_price and unit_price columns
        p1 = item.get("item_price", 0.0)
        p2 = item.get("unit_price", 0.0)
        if abs(p1 - target_price) < 0.01 or abs(p2 - target_price) < 0.01:
            correct_price_sale = True
            break
            
    if correct_price_sale:
        score += 30
        feedback.append(f"Transaction processed with correct manual price ${target_price}.")
    else:
        feedback.append(f"Transaction price incorrect (Found: {[i.get('item_price') for i in sold_items]}).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }