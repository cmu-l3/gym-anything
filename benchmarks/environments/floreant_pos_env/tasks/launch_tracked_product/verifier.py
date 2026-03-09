#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_launch_tracked_product(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created 'Wagyu Patty' and 'Brioche Bun' inventory items.
    2. Created 'Wagyu Burger' menu item.
    3. Linked them (Recipe).
    4. Processed a sale.
    5. CRITICAL: Inventory count dropped from 100 -> 99.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    score = 0
    feedback = []

    # 1. Verify Menu Item Creation (20 pts)
    if result.get('menu_item_found'):
        score += 20
        feedback.append("Menu item 'Wagyu Burger' created.")
    else:
        feedback.append("Menu item 'Wagyu Burger' NOT found.")

    # 2. Verify Sales Processing (20 pts)
    sales_count = result.get('sales_count', 0)
    if sales_count > 0:
        score += 20
        feedback.append(f"Sale processed successfully ({sales_count} ticket(s)).")
    else:
        feedback.append("No settled tickets found for 'Wagyu Burger'.")

    # 3. Verify Inventory Existence (20 pts)
    inventory = result.get('inventory', {})
    patty_stock = inventory.get('Wagyu Patty')
    bun_stock = inventory.get('Brioche Bun')

    items_exist = (patty_stock is not None) and (bun_stock is not None)
    if items_exist:
        score += 20
        feedback.append("Inventory items 'Wagyu Patty' and 'Brioche Bun' exist.")
    else:
        feedback.append("One or more inventory items missing.")

    # 4. Verify Inventory Deduction (40 pts)
    # This proves the Recipe link was created AND the sale triggered the deduction.
    # Initial stock was 100. Expected is 99.
    deduction_correct = False
    
    if items_exist:
        # Check Patty
        if patty_stock == 99.0:
            feedback.append("Wagyu Patty stock correctly deducted (100 -> 99).")
            score += 20
        elif patty_stock == 100.0:
            feedback.append("Wagyu Patty stock did not change (Recipe link missing?).")
        else:
            feedback.append(f"Wagyu Patty stock is {patty_stock} (Expected 99).")

        # Check Bun
        if bun_stock == 99.0:
            feedback.append("Brioche Bun stock correctly deducted (100 -> 99).")
            score += 20
        elif bun_stock == 100.0:
            feedback.append("Brioche Bun stock did not change.")
        else:
            feedback.append(f"Brioche Bun stock is {bun_stock} (Expected 99).")

        if patty_stock == 99.0 and bun_stock == 99.0:
            deduction_correct = True

    # Final logic
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }