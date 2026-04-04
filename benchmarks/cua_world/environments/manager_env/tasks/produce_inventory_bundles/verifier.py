#!/usr/bin/env python3
"""
Verifier for produce_inventory_bundles task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_produce_inventory_bundles(traj, env_info, task_info):
    """
    Verify that the agent enabled the module, created the item, and produced the bundles.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    manager_data = result.get('manager_data', {})
    initial_bundle_exists = result.get('initial_bundle_exists', False)
    
    score = 0
    feedback = []
    
    # 1. Anti-gaming check: Item shouldn't have existed before
    if initial_bundle_exists:
        feedback.append("WARNING: 'Beverage Bundle' existed before task started.")
        # We don't fail immediately but this is suspicious if the environment wasn't clean
    
    # 2. Verify Module Enabled (20 pts)
    if manager_data.get('module_enabled'):
        score += 20
        feedback.append("Production Orders module enabled.")
    else:
        feedback.append("Production Orders module NOT enabled.")

    # 3. Verify Item Created (20 pts)
    if manager_data.get('item_created'):
        score += 20
        feedback.append("Inventory Item 'Beverage Bundle' created.")
    else:
        feedback.append("Inventory Item 'Beverage Bundle' NOT found.")

    # 4. Verify Production Order Exists (20 pts)
    order_details = manager_data.get('order_details', {})
    if manager_data.get('order_created'):
        score += 20
        feedback.append("Production Order found.")
        
        # 5. Verify Output Quantity (10 pts)
        qty = order_details.get('finished_qty', 0)
        item_name = order_details.get('finished_item', '')
        if "Beverage Bundle" in item_name and qty == 10:
            score += 10
            feedback.append("Correct finished good and quantity (10).")
        else:
            feedback.append(f"Incorrect finished good ({item_name}) or quantity ({qty}).")
            
        # 6. Verify Inputs (30 pts)
        inputs = order_details.get('inputs', [])
        chai_found = any(i['name'] == 'Chai' and i['qty'] == 10 for i in inputs)
        chang_found = any(i['name'] == 'Chang' and i['qty'] == 10 for i in inputs)
        
        if chai_found:
            score += 15
            feedback.append("Input: Chai (10) correct.")
        else:
            feedback.append("Input: Chai (10) missing or incorrect.")
            
        if chang_found:
            score += 15
            feedback.append("Input: Chang (10) correct.")
        else:
            feedback.append("Input: Chang (10) missing or incorrect.")
            
    else:
        feedback.append("No Production Order found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }