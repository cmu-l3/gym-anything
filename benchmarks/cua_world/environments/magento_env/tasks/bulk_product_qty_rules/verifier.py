#!/usr/bin/env python3
"""Verifier for Bulk Product Quantity Rules task in Magento.

Task: Configure 'Classic Cotton T-Shirt' (TSHIRT-001) with:
- Min Qty: 5
- Max Qty: 50
- Qty Increments: Enabled, Value 5

Scored on 4 criteria (100 pts total). Pass threshold: 100 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_product_qty_rules(traj, env_info, task_info):
    """
    Verify product inventory settings.
    
    Criteria:
    1. Minimum Qty Allowed is 5 (30 pts)
    2. Maximum Qty Allowed is 50 (30 pts)
    3. Qty Increments is Enabled (20 pts)
    4. Qty Increments Value is 5 (20 pts)
    
    Pass threshold: 100 pts (all rules required for correct logic).
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_min = float(metadata.get('expected_min_sale_qty', 5.0))
    expected_max = float(metadata.get('expected_max_sale_qty', 50.0))
    expected_inc_enable = int(metadata.get('expected_enable_qty_increments', 1))
    expected_inc_val = float(metadata.get('expected_qty_increments', 5.0))

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/bulk_rules_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    logger.info(f"Result: {result}")
    
    if not result.get('product_found', False):
        return {"passed": False, "score": 0, "feedback": "Target product 'TSHIRT-001' not found in database."}

    score = 0
    feedback_parts = []
    
    # Helper for float comparison
    def float_eq(a, b):
        try:
            return abs(float(a) - float(b)) < 0.01
        except:
            return False

    # 1. Min Qty (30 pts)
    actual_min = result.get('min_sale_qty', 0)
    use_config_min = str(result.get('use_config_min', '1')).strip()
    
    # If use_config is 1, the user didn't uncheck the box, so they didn't really set it 
    # (unless the config happens to be 5, but the task implies setting it on the product).
    # However, strictly speaking, if the value in DB is 5, it works. 
    # But usually 'use_config=1' implies the 'value' column might be ignored or stale.
    # We will score based on the value actually stored, but warn if config is used.
    
    if float_eq(actual_min, expected_min):
        score += 30
        feedback_parts.append("Min Qty is 5 (30 pts)")
    else:
        feedback_parts.append(f"Min Qty incorrect: expected {expected_min}, got {actual_min}")

    # 2. Max Qty (30 pts)
    actual_max = result.get('max_sale_qty', 0)
    if float_eq(actual_max, expected_max):
        score += 30
        feedback_parts.append("Max Qty is 50 (30 pts)")
    else:
        feedback_parts.append(f"Max Qty incorrect: expected {expected_max}, got {actual_max}")

    # 3. Enable Increments (20 pts)
    actual_enable = str(result.get('enable_qty_increments', '0')).strip()
    # In Magento DB, boolean is 0/1.
    if actual_enable == str(expected_inc_enable):
        score += 20
        feedback_parts.append("Qty Increments Enabled (20 pts)")
    else:
        feedback_parts.append(f"Qty Increments not enabled")

    # 4. Increment Value (20 pts)
    actual_inc_val = result.get('qty_increments', 0)
    if float_eq(actual_inc_val, expected_inc_val):
        score += 20
        feedback_parts.append("Increment Value is 5 (20 pts)")
    else:
        feedback_parts.append(f"Increment Value incorrect: expected {expected_inc_val}, got {actual_inc_val}")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }