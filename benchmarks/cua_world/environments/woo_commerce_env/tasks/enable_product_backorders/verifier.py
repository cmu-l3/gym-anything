#!/usr/bin/env python3
"""
Verifier for enable_product_backorders task.

Criteria:
1. Product Backorders setting is 'notify' (Allow, but notify customer).
2. Low stock threshold is specifically '5'.
3. Stock management is still enabled ('yes').
4. Stock status is 'onbackorder' (System handles this, but good to verify).
5. Modification happened during the task window.
6. No other products were modified.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_product_backorders(traj, env_info, task_info):
    """
    Verify the backorder configuration task.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
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

    # 2. Check Prerequisites
    if not result.get('product_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target product 'Wireless Bluetooth Headphones' (WBH-001) could not be found."
        }

    score = 0
    max_score = 100
    feedback_parts = []
    passed = False

    # 3. Verify Modification Time (Anti-gaming)
    mod_ts = result.get('modified_timestamp', 0)
    start_ts = result.get('task_start_timestamp', 0)
    
    if mod_ts > start_ts:
        feedback_parts.append("Product was modified during task.")
    else:
        # If not modified, they certainly failed
        return {
            "passed": False,
            "score": 0,
            "feedback": "Product was not modified during the task session."
        }

    # 4. Verify Backorder Setting (40 points)
    # Expected: 'notify'
    backorders = result.get('backorders', '')
    if backorders == 'notify':
        score += 40
        feedback_parts.append("Backorders set to 'Allow, but notify customer' (+40).")
    elif backorders == 'yes':
        score += 10
        feedback_parts.append("Backorders set to 'Allow' but missing notification (-30).")
    else:
        feedback_parts.append(f"Backorders setting incorrect: found '{backorders}' (expected 'notify').")

    # 5. Verify Low Stock Threshold (30 points)
    # Expected: '5'
    low_stock = str(result.get('low_stock_amount', ''))
    if low_stock == '5':
        score += 30
        feedback_parts.append("Low stock threshold set to 5 (+30).")
    else:
        feedback_parts.append(f"Low stock threshold incorrect: found '{low_stock}' (expected 5).")

    # 6. Verify Stock Management (10 points)
    # Must remain 'yes'
    manage_stock = result.get('manage_stock', '')
    if manage_stock == 'yes':
        score += 10
        feedback_parts.append("Stock management active (+10).")
    else:
        feedback_parts.append("Stock management disabled (-10).")

    # 7. Verify Stock Status (10 points)
    # Should automatically become 'onbackorder' if qty <= 0 and backorders allowed
    stock_status = result.get('stock_status', '')
    if stock_status == 'onbackorder':
        score += 10
        feedback_parts.append("Stock status correctly updated to 'On backorder' (+10).")
    elif stock_status == 'instock':
        feedback_parts.append("Stock status is 'In stock' (unexpected for 0 quantity).")
    elif stock_status == 'outofstock':
        # This usually means backorders weren't enabled correctly
        feedback_parts.append("Stock status is 'Out of stock'.")

    # 8. Verify Collateral Damage (10 points)
    other_mods = result.get('other_products_modified_count', 0)
    if other_mods == 0:
        score += 10
        feedback_parts.append("No other products modified (+10).")
    else:
        feedback_parts.append(f"Warning: {other_mods} other products were modified.")

    # 9. Final Scoring
    # Threshold: 70 points
    # Must have the backorder setting correct ('notify') to essentially 'pass' the intent
    passed = (score >= 70) and (backorders == 'notify')

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }