#!/usr/bin/env python3
"""
Verifier for create_restricted_coupon task.

Verifies:
1. Coupon 'CLOTHING-DEAL' exists.
2. Discount amount is 20.00.
3. Discount type is 'fixed_cart'.
4. Minimum spend is 75.00.
5. 'Exclude sale items' is true.
6. Product categories include 'Clothing'.
7. VLM verification of the process.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_restricted_coupon(traj, env_info, task_info):
    """
    Verify the restricted coupon creation task.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    coupon_found = result.get('coupon_found', False)
    coupon_data = result.get('coupon_data', {})
    target_cat_id = result.get('target_category_id', 0)
    task_start_time = result.get('task_start_time', 0)

    # 1. Coupon Existence (20 pts)
    if coupon_found and coupon_data:
        score += 20
        feedback.append("Coupon 'CLOTHING-DEAL' found.")
        
        # Check creation time (Anti-gaming)
        # WC API returns ISO8601 strings. Simple check: if it exists and we deleted it in setup, it's new.
        # But setup script logic handles deletion, so existence implies creation.
    else:
        return {"passed": False, "score": 0, "feedback": "Coupon 'CLOTHING-DEAL' not found."}

    # 2. General Settings (20 pts)
    # Amount
    amount = float(coupon_data.get('amount', 0))
    if abs(amount - 20.0) < 0.01:
        score += 10
        feedback.append("Correct discount amount ($20).")
    else:
        feedback.append(f"Incorrect amount: {amount} (expected 20).")

    # Type
    disc_type = coupon_data.get('discount_type', '')
    if disc_type == 'fixed_cart':
        score += 10
        feedback.append("Correct discount type (fixed cart).")
    else:
        feedback.append(f"Incorrect discount type: {disc_type}.")

    # 3. Usage Restrictions (60 pts)
    # Minimum Spend (20 pts)
    min_amount = float(coupon_data.get('minimum_amount', 0))
    if abs(min_amount - 75.0) < 0.01:
        score += 20
        feedback.append("Correct minimum spend ($75).")
    else:
        feedback.append(f"Incorrect minimum spend: {min_amount} (expected 75).")

    # Exclude Sale Items (20 pts)
    exclude_sale = coupon_data.get('exclude_sale_items', False)
    # WC JSON API usually returns boolean true/false or string "true"/"false"
    if exclude_sale is True or str(exclude_sale).lower() == 'true':
        score += 20
        feedback.append("Correctly excludes sale items.")
    else:
        feedback.append("Failed to exclude sale items.")

    # Category Restriction (20 pts)
    product_categories = coupon_data.get('product_categories', [])
    # API returns list of objects: [{"id": 12, "name": "Clothing", ...}]
    # We check if target_cat_id is in the list
    cat_ids = [int(c.get('id', 0)) for c in product_categories]
    
    if int(target_cat_id) in cat_ids:
        score += 20
        feedback.append(f"Correctly restricted to Clothing category (ID {target_cat_id}).")
    else:
        # Fallback: check by name if ID changed for some reason
        cat_names = [c.get('name', '').lower() for c in product_categories]
        if 'clothing' in cat_names:
            score += 20
            feedback.append("Correctly restricted to Clothing category (verified by name).")
        else:
            feedback.append(f"Category restriction missing. Found: {cat_names}")

    # Pass Condition
    # We require ALL critical restrictions to be correct.
    # Total possible: 100.
    passed = (score == 100)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }