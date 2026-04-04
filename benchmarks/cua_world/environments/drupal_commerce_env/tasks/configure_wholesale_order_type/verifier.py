#!/usr/bin/env python3
"""
Verifier for configure_wholesale_order_type task.

Verifies:
1. 'Wholesale' order type exists with 'Fulfillment' workflow.
2. 'Wholesale Product' order item type exists, linked to 'Wholesale' order type.
3. Order item type uses 'Product variation' as purchasable entity.
4. An order exists for user 'mikewilson' with type 'Wholesale'.
5. That order contains items.
"""

import json
import logging
import os
import tempfile
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_wholesale_order_type(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # Data from export
    order_types = result.get('order_types', {})
    order_item_types = result.get('order_item_types', {})
    orders = result.get('orders', {})
    target_users = result.get('target_users', {})
    
    # 1. Identify the created Order Type
    # We look for one with "wholesale" in the ID or Label
    found_order_type = None
    for ot_id, ot_data in order_types.items():
        if 'wholesale' in ot_id.lower() or 'wholesale' in ot_data.get('label', '').lower():
            found_order_type = ot_data
            break
    
    if found_order_type:
        score += 20
        feedback_parts.append(f"Order type '{found_order_type['label']}' found.")
        
        # Check Workflow
        workflow = found_order_type.get('workflow')
        if workflow == 'order_fulfillment':
            score += 15
            feedback_parts.append("Workflow is correctly set to 'Fulfillment'.")
        else:
            feedback_parts.append(f"Workflow incorrect: expected 'order_fulfillment', got '{workflow}'.")
    else:
        feedback_parts.append("No order type named 'Wholesale' found.")

    # 2. Identify the Order Item Type
    # Should be named "Wholesale Product" or similar, and linked to the order type found above
    found_item_type = None
    if found_order_type:
        target_ot_id = found_order_type['id']
        for oit_id, oit_data in order_item_types.items():
            # Check linkage
            if oit_data.get('orderType') == target_ot_id:
                found_item_type = oit_data
                break
        
        if not found_item_type:
            # Fallback: look by name even if linkage is broken, for partial credit logic
            for oit_id, oit_data in order_item_types.items():
                 if 'wholesale' in oit_data.get('label', '').lower():
                    found_item_type = oit_data
                    break

    if found_item_type:
        score += 20
        feedback_parts.append(f"Order item type '{found_item_type['label']}' found.")
        
        # Check Linkage (if we found it by name/fallback)
        if found_order_type and found_item_type.get('orderType') == found_order_type['id']:
            feedback_parts.append("Order item type is correctly linked to order type.")
        elif found_order_type:
             feedback_parts.append(f"Order item type NOT linked to Wholesale order type (linked to '{found_item_type.get('orderType')}').")
             score -= 5 # Penalty for finding item type but wrong link

        # Check Purchasable Entity Type
        pet = found_item_type.get('purchasableEntityType')
        if pet == 'commerce_product_variation':
            score += 10
            feedback_parts.append("Purchasable entity type is correct (Product variation).")
        else:
            feedback_parts.append(f"Purchasable entity type incorrect: got '{pet}'.")
    else:
        feedback_parts.append("No matching Order item type found.")

    # 3. Check for the Order
    target_uid = target_users.get('mikewilson')
    if not target_uid:
        return {"passed": False, "score": 0, "feedback": "CRITICAL: Target user 'mikewilson' not found in system."}

    found_order = None
    if found_order_type:
        target_ot_id = found_order_type['id']
        # Iterate orders to find one for this user and type
        for o_id, o_data in orders.items():
            if str(o_data.get('uid')) == str(target_uid) and o_data.get('type') == target_ot_id:
                found_order = o_data
                break
    
    if found_order:
        score += 20
        feedback_parts.append("Wholesale order for 'mikewilson' found.")
        
        # Check if it has items
        item_count = found_order.get('item_count', 0)
        if item_count > 0:
            score += 15
            feedback_parts.append(f"Order contains {item_count} item(s).")
        else:
            feedback_parts.append("Order is empty (no items added).")
    else:
        feedback_parts.append("No order of type 'Wholesale' found for user 'mikewilson'.")

    # Pass logic
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }