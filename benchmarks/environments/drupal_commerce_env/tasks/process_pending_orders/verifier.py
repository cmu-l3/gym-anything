#!/usr/bin/env python3
"""
Verifier for Process Pending Orders task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_pending_orders(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_orders_meta = metadata.get('orders', [])

    # Map expected data by SKU/Customer for easy lookup
    # Key: "customer|sku" -> expected_states
    expected_map = {}
    for item in expected_orders_meta:
        key = f"{item['customer']}|{item['product_sku']}"
        expected_map[key] = item['expected_states']

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        if result.get("error"):
            return {"passed": False, "score": 0, "feedback": f"Setup or Export failed: {result.get('error')}"}

        actual_orders = result.get("orders", [])
        
        score = 0
        max_score = 100
        points_per_order = 25
        feedback_parts = []
        
        orders_processed_correctly = 0
        
        # We need to verify 4 specific orders
        if len(actual_orders) != 4:
            feedback_parts.append(f"Warning: Expected 4 orders tracked, found {len(actual_orders)}")

        for order in actual_orders:
            oid = order['id']
            customer = order['customer']
            sku = order['sku']
            state = order.get('final_state', 'unknown')
            
            key = f"{customer}|{sku}"
            
            if key not in expected_map:
                feedback_parts.append(f"Order #{oid} ({customer}/{sku}) was not part of the task setup.")
                continue
                
            expected_states = expected_map[key]
            
            if state in expected_states:
                score += points_per_order
                orders_processed_correctly += 1
                feedback_parts.append(f"Order #{oid} ({customer}/{sku}): Correctly set to '{state}'")
            else:
                feedback_parts.append(f"Order #{oid} ({customer}/{sku}): Incorrect state '{state}' (Expected: {expected_states})")

        # Gate: If nothing changed (all draft), fail hard
        # 'draft' is usually the default state.
        all_draft = all(o.get('final_state') == 'draft' for o in actual_orders)
        if all_draft:
            return {
                "passed": False,
                "score": 0,
                "feedback": "All orders are still in 'draft' state. No actions were performed."
            }

        passed = score >= 50 and orders_processed_correctly >= 2

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}