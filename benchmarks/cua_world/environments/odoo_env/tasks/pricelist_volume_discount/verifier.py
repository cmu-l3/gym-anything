#!/usr/bin/env python3
"""
Verifier for pricelist_volume_discount task.

Points Distribution (100 total):
- Pricelist 'Wholesale Partner - Tier 2' exists: 10 pts
- Pricelists feature enabled (inferred by success/count): 10 pts
- Correct items (18 pts per product * 3 products): 54 pts
    - Each tier (1, 10, 50/25/100) correct: 6 pts
- Assigned to Customer: 20 pts
- Items on correct pricelist link: 6 pts
"""

import json
import logging
import tempfile
import os

logger = logging.getLogger(__name__)

def verify_pricelist_volume_discount(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback = []
    
    # 1. Feature Enabled & Pricelist Exists
    # If the agent created a pricelist, the feature is implicitly enabled or defaults allowed it.
    # We check if count increased or specific pricelist found.
    pricelist_found = result.get("pricelist_found", False)
    initial_count = result.get("initial_pricelist_count", 0)
    current_count = result.get("current_pricelist_count", 0)
    
    if pricelist_found:
        score += 10
        feedback.append("Pricelist found.")
    else:
        feedback.append("Pricelist 'Wholesale Partner - Tier 2' NOT found.")
    
    # Bonus for enabling/creating (if count increased)
    if current_count > initial_count:
        score += 10
        feedback.append("Pricelist count increased (feature enabled).")
    elif pricelist_found:
        # If found but count didn't increase (unlikely unless they renamed default), still give points
        score += 10
    else:
        feedback.append("No new pricelist created.")

    # 2. Verify Items
    # Target structure from metadata
    products_target = {
        "Industrial Shelving Unit": {
            1: 299.00, 10: 269.00, 50: 239.00
        },
        "Ergonomic Office Chair": {
            1: 199.00, 10: 179.00, 50: 159.00
        },
        "Corrugated Shipping Box - Large": {
            1: 9.50, 25: 8.00, 100: 6.50
        }
    }
    
    items = result.get("pricelist_items", [])
    
    # Helper to fuzzy match product name
    def match_product(name, target_map):
        for k in target_map.keys():
            if k.lower() in name.lower() or name.lower() in k.lower():
                return k
        return None

    correct_items_count = 0
    total_tiers = 9 # 3 prods * 3 tiers
    
    # We need to track which tiers were found to avoid double counting
    # (Product, MinQty) -> Found
    found_tiers = set()
    linked_correctly = True

    for item in items:
        p_name = item.get("product", "")
        min_qty = item.get("min_qty", 0)
        price = item.get("price", 0.0)
        
        target_key = match_product(p_name, products_target)
        if target_key:
            target_tiers = products_target[target_key]
            # Check if this min_qty is in target
            # XMLRPC returns float for some numbers, ensuring int comparison for qty
            mq_int = int(min_qty)
            if mq_int in target_tiers:
                expected_price = target_tiers[mq_int]
                # Tolerance check
                if abs(price - expected_price) < 0.1:
                    if (target_key, mq_int) not in found_tiers:
                        score += 6
                        correct_items_count += 1
                        found_tiers.add((target_key, mq_int))
                        feedback.append(f"Correct: {target_key} @ {mq_int} units = ${price}")
                else:
                    feedback.append(f"Incorrect Price: {target_key} @ {mq_int} units. Got ${price}, expected ${expected_price}")
            else:
                # Extra tier or wrong quantity step
                pass
        else:
            # Item for unknown product
            pass

    # 3. Linked Correctly
    # If we found items, they came from the pricelist query in export script.
    # So if correct_items_count > 0, they are linked.
    if correct_items_count == 9:
        score += 6
        feedback.append("All items linked correctly.")
    elif correct_items_count > 0:
        # Partial link points
        score += int(6 * (correct_items_count / 9))

    # 4. Customer Assignment
    target_pl_id = result.get("target_pricelist_id")
    assigned_pl_id = result.get("assigned_pricelist_id")
    
    if target_pl_id and assigned_pl_id and target_pl_id == assigned_pl_id:
        score += 20
        feedback.append("Customer assigned to correct pricelist.")
    elif assigned_pl_id:
        feedback.append(f"Customer assigned to wrong pricelist ID {assigned_pl_id} (Expected {target_pl_id}).")
    else:
        feedback.append("Customer has no pricelist assigned (or default).")

    # Final Score Calc
    return {
        "passed": score >= 65,
        "score": score,
        "feedback": "\n".join(feedback)
    }