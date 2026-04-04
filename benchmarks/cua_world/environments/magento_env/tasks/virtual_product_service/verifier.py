#!/usr/bin/env python3
"""Verifier for Virtual Product Service task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_virtual_product_service(traj, env_info, task_info):
    """
    Verify creation of the Virtual Product service.
    
    Criteria:
    1. Product exists with SKU 'SVC-HT-INSTALL' (20 pts)
    2. Product Type is 'virtual' (25 pts) - CRITICAL for this task
    3. Price is 199.00 (15 pts)
    4. Assigned to Electronics category (20 pts)
    5. Visibility is Catalog, Search (10 pts)
    6. Stock/Qty is > 0 (10 pts)
    
    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get expected metadata
    metadata = task_info.get('metadata', {})
    expected_sku = metadata.get('expected_sku', 'SVC-HT-INSTALL')
    expected_type = metadata.get('expected_type', 'virtual')
    expected_price = float(metadata.get('expected_price', 199.00))
    
    try:
        # Load result
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/virtual_product_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

    logger.info(f"Verification Result Data: {result}")

    score = 0
    feedback_parts = []
    
    # 1. Product Existence (20 pts)
    product_found = result.get('product_found', False)
    is_newly_created = result.get('is_newly_created', False)
    
    if product_found and is_newly_created:
        score += 20
        feedback_parts.append("Product created successfully (20 pts)")
    elif product_found:
        score += 10
        feedback_parts.append("Product found but not newly created (10 pts)")
    else:
        feedback_parts.append(f"Product with SKU '{expected_sku}' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Product Type (25 pts)
    # Must be 'virtual'
    type_id = result.get('type_id', 'unknown')
    if type_id == expected_type:
        score += 25
        feedback_parts.append("Correct Product Type: Virtual (25 pts)")
    else:
        feedback_parts.append(f"Incorrect Product Type: expected '{expected_type}', got '{type_id}'")

    # 3. Price (15 pts)
    try:
        price_val = float(result.get('price', 0))
        if abs(price_val - expected_price) < 0.1:
            score += 15
            feedback_parts.append("Price is correct (15 pts)")
        else:
            feedback_parts.append(f"Price mismatch: expected {expected_price}, got {price_val}")
    except:
        feedback_parts.append("Price format error")

    # 4. Category (20 pts)
    in_electronics = result.get('is_in_electronics_category', False)
    if in_electronics:
        score += 20
        feedback_parts.append("Assigned to 'Electronics' category (20 pts)")
    else:
        feedback_parts.append("Not assigned to 'Electronics' category")

    # 5. Visibility (10 pts)
    # 4 = Catalog, Search
    visibility = str(result.get('visibility', '0'))
    if visibility == '4':
        score += 10
        feedback_parts.append("Visibility correct (10 pts)")
    else:
        feedback_parts.append(f"Visibility incorrect (expected 4, got {visibility})")

    # 6. Stock/Qty (10 pts)
    try:
        qty = float(result.get('qty', 0))
        if qty > 0:
            score += 10
            feedback_parts.append("Stock quantity set (10 pts)")
        else:
            feedback_parts.append("Stock quantity is 0")
    except:
        pass

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }