#!/usr/bin/env python3
"""
Verifier for Catalog Price Rule task in Magento.

Task: Create 'SUMMER_CLEARANCE_2025' catalog price rule.
- 20% discount
- Electronics category
- NOT LOGGED IN + General groups
- Specific dates, priority, stop processing
- MUST APPLY RULE (index)
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_catalog_price_rule(traj, env_info, task_info):
    """
    Verify catalog price rule creation and application.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/catalog_rule_result.json", tmp.name)
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
    
    # 1. Rule Exists (Gate) - 15 pts
    if not result.get('rule_found', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Rule 'SUMMER_CLEARANCE_2025' not found in database."
        }
    
    score += 15
    feedback_parts.append("Rule created")

    # 2. Discount Amount & Type - 15 pts
    action = result.get('simple_action', '')
    amount = float(result.get('discount_amount', 0) or 0)
    
    if action == 'by_percent' and abs(amount - 20.0) < 0.01:
        score += 15
        feedback_parts.append("Correct discount (20% off)")
    else:
        feedback_parts.append(f"Incorrect discount: Type={action}, Amount={amount} (Expected by_percent, 20)")

    # 3. Date Range - 10 pts
    # Dates usually stored as YYYY-MM-DD
    from_date = result.get('from_date', '')
    to_date = result.get('to_date', '')
    
    if '2025-06-01' in from_date and '2025-08-31' in to_date:
        score += 10
        feedback_parts.append("Correct date range")
    else:
        feedback_parts.append(f"Incorrect dates: {from_date} to {to_date}")

    # 4. Priority & Stop Processing - 10 pts
    sort_order = str(result.get('sort_order', ''))
    stop_processing = str(result.get('stop_rules_processing', ''))
    
    if sort_order == '2' and stop_processing == '1':
        score += 10
        feedback_parts.append("Correct priority and stop processing")
    else:
        feedback_parts.append(f"Settings mismatch: Priority={sort_order}, Stop={stop_processing}")

    # 5. Customer Groups - 20 pts
    # Expected: 0 (NOT LOGGED IN) and 1 (General)
    groups = result.get('customer_groups', [])
    expected_groups = {0, 1}
    actual_groups = set(groups)
    
    if actual_groups == expected_groups:
        score += 20
        feedback_parts.append("Correct customer groups (NOT LOGGED IN, General)")
    elif expected_groups.issubset(actual_groups):
        score += 10
        feedback_parts.append("Partial credit: Required groups included, but extra groups also selected")
    else:
        feedback_parts.append(f"Incorrect groups selected: {groups}")

    # 6. Conditions (Category) - 15 pts
    if result.get('has_electronics_condition', False):
        score += 15
        feedback_parts.append("Correct category condition (Electronics)")
    else:
        feedback_parts.append("Electronics category condition missing")

    # 7. Rule Applied (Indexed) - 15 pts
    # If the user saved but didn't click "Apply Rules", this table is empty for the rule
    applied_count = int(result.get('applied_product_count', 0))
    if applied_count > 0:
        score += 15
        feedback_parts.append("Rule successfully applied (indexed)")
    else:
        feedback_parts.append("Rule saved but NOT applied. You must click 'Apply Rules' for it to take effect.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }