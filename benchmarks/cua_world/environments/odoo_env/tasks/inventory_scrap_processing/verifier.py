#!/usr/bin/env python3
"""
Verifier for inventory_scrap_processing task.

Verifies:
1. Scrap orders created and validated for 3 products.
2. Correct quantities scrapped.
3. Inventory levels reflect the scrap.
4. Anti-gaming: Ensure new records were created.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_scrap_processing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {result['error']}"}

    score = 0
    feedback = []
    
    products = result.get("products", {})
    scrap_delta = result.get("scrap_count_delta", 0)

    # Anti-gaming check
    if scrap_delta < 1:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No new scrap orders were created (Total scrap count did not increase)."
        }

    # Scoring per product
    # Helmet (Total 33: 18 order + 10 qty + 5 stock)
    helmet = products.get("Industrial Safety Helmet - Class E", {})
    if helmet.get("scrap_order_exists"):
        score += 18
        if helmet.get("scrap_qty_correct"):
            score += 10
            feedback.append("Helmet: Scrap order correct (25 units).")
        else:
            feedback.append(f"Helmet: Wrong qty (scrapped {helmet.get('actual_scrap_qty')}, expected 25).")
        
        if helmet.get("stock_correct"):
            score += 5
        else:
            feedback.append(f"Helmet: Stock mismatch (current {helmet.get('current_stock')}).")
    else:
        feedback.append("Helmet: No validated scrap order found.")

    # Pallet Jack (Total 33: 18 order + 10 qty + 5 stock)
    jack = products.get("Heavy Duty Pallet Jack - 5500lb", {})
    if jack.get("scrap_order_exists"):
        score += 18
        if jack.get("scrap_qty_correct"):
            score += 10
            feedback.append("Pallet Jack: Scrap order correct (4 units).")
        else:
            feedback.append(f"Pallet Jack: Wrong qty (scrapped {jack.get('actual_scrap_qty')}, expected 4).")
        
        if jack.get("stock_correct"):
            score += 5
        else:
            feedback.append(f"Pallet Jack: Stock mismatch (current {jack.get('current_stock')}).")
    else:
        feedback.append("Pallet Jack: No validated scrap order found.")

    # Box (Total 34: 18 order + 10 qty + 6 stock)
    box = products.get("Corrugated Shipping Box - 24x18x12", {})
    if box.get("scrap_order_exists"):
        score += 18
        if box.get("scrap_qty_correct"):
            score += 10
            feedback.append("Shipping Box: Scrap order correct (85 units).")
        else:
            feedback.append(f"Shipping Box: Wrong qty (scrapped {box.get('actual_scrap_qty')}, expected 85).")
        
        if box.get("stock_correct"):
            score += 6
        else:
            feedback.append(f"Shipping Box: Stock mismatch (current {box.get('current_stock')}).")
    else:
        feedback.append("Shipping Box: No validated scrap order found.")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }