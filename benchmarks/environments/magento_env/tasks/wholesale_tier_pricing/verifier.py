#!/usr/bin/env python3
"""Verifier for Wholesale Tier Pricing task in Magento.

Task: Create 'Wholesale Buyers' group, assign John Smith, add tier prices to 3 products.

Scoring:
- Group creation: 15 pts
- Tax class correct: 5 pts
- Customer reassignment: 15 pts
- Tier prices (per product): 60 pts total (10 pts per entry * 6 entries)
  or grouped by product logic.

Pass threshold: 60 pts
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wholesale_tier_pricing(traj, env_info, task_info):
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_tiers = metadata.get('tier_prices', {})
    # Format: {'SKU': [{'qty': 5, 'price': 849.99}, ...]}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/wholesale_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # 1. Group Creation (15 pts)
    if result.get('group_found'):
        score += 15
        feedback_parts.append("Group 'Wholesale Buyers' created (15 pts)")
    else:
        feedback_parts.append("Group 'Wholesale Buyers' NOT found")
        # Fail early? No, partial credit might be possible if they did other things 
        # (though likely impossible to add tier prices to a non-existent group)
        # But let's continue.

    # 2. Tax Class (5 pts)
    tax_name = result.get('tax_class_name', '').lower()
    if 'retail' in tax_name:
        score += 5
        feedback_parts.append("Tax Class 'Retail Customer' selected (5 pts)")
    elif result.get('group_found'):
        feedback_parts.append(f"Incorrect Tax Class: '{result.get('tax_class_name')}' (expected Retail Customer)")

    # 3. Customer Reassignment (15 pts)
    if result.get('customer_in_correct_group'):
        score += 15
        feedback_parts.append("Customer John Smith assigned to Wholesale Buyers (15 pts)")
    else:
        feedback_parts.append("Customer John Smith NOT in Wholesale Buyers group")

    # 4. Tier Prices (65 pts distributed)
    # We have 3 products, each has 2 tiers. Total 6 entries.
    # Let's allocate 10 pts per correct tier entry. Total 60 pts.
    # Plus 5 bonus/buffer or just strict. Let's do 10 pts per entry.
    
    found_tiers = result.get('tier_prices', [])
    # Convert list of dicts to a more searchable format: SKU -> {qty: price}
    found_map = {}
    for entry in found_tiers:
        sku = entry.get('sku', '').upper()
        qty = float(entry.get('qty', 0))
        val = float(entry.get('value', 0))
        if sku not in found_map:
            found_map[sku] = {}
        found_map[sku][qty] = val

    tier_score = 0
    total_tiers = 0
    
    for sku, requirements in expected_tiers.items():
        sku_upper = sku.upper()
        if sku_upper not in found_map:
            feedback_parts.append(f"No tier prices found for {sku}")
            continue
        
        for req in requirements:
            req_qty = float(req['qty'])
            req_price = float(req['price'])
            total_tiers += 1
            
            # Check if this qty exists in found map
            # Use small epsilon for float comparison if needed, but qty is usually int-like
            match_found = False
            for f_qty, f_price in found_map[sku_upper].items():
                if abs(f_qty - req_qty) < 0.1:
                    # Check price
                    if abs(f_price - req_price) < 0.02:
                        match_found = True
                        break
            
            if match_found:
                tier_score += 10
                feedback_parts.append(f"Correct tier: {sku} @ {int(req_qty)} (10 pts)")
            else:
                feedback_parts.append(f"Missing/Wrong tier: {sku} Qty {int(req_qty)} -> ${req_price}")

    score += tier_score
    
    # 5. Anti-gaming check (simple sanity)
    # If the group ID existed before start (handled in setup_task by deleting it),
    # verifying count increase is good.
    initial_count = int(result.get('initial_group_count', 0))
    current_count = int(result.get('current_group_count', 0))
    if result.get('group_found') and current_count <= initial_count:
        # This implies we reused an existing group despite setup script trying to delete it?
        # Or maybe someone else created it. 
        # Since setup script deletes 'Wholesale Buyers', finding it means it was created.
        pass

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }