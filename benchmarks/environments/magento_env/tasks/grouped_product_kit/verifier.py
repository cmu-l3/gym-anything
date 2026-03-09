#!/usr/bin/env python3
"""Verifier for Grouped Product Kit task in Magento."""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_grouped_product_kit(traj, env_info, task_info):
    """
    Verify that the grouped product was created correctly.
    
    Criteria:
    1. Product 'HOMEGYM-KIT-001' exists (25 pts)
    2. Product type is 'grouped' (20 pts)
    3. Product status is Enabled (10 pts)
    4. Product visibility is Catalog, Search (5 pts)
    5. Product is in 'Sports' category (10 pts)
    6. Child products linked: YOGA-001 (10 pts)
    7. Child products linked: BOTTLE-001 (10 pts)
    8. Child products linked: TSHIRT-001 (10 pts)
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_sku = metadata.get('expected_sku', 'HOMEGYM-KIT-001')
    expected_type = metadata.get('expected_type', 'grouped')
    expected_name = metadata.get('expected_name', 'Home Gym Starter Kit')
    expected_category = metadata.get('expected_category', 'Sports')
    
    # Load result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/grouped_product_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []
    
    product_found = result.get('product_found', False)
    product = result.get('product', {})
    
    # Criterion 1: Product Exists (25 pts)
    if product_found:
        score += 25
        feedback_parts.append("Product found")
    else:
        feedback_parts.append("Product NOT found")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Type is Grouped (20 pts)
    actual_type = product.get('type', '')
    if actual_type == expected_type:
        score += 20
        feedback_parts.append("Type is grouped")
    else:
        feedback_parts.append(f"Type mismatch: expected {expected_type}, got {actual_type}")

    # Criterion 3: Status Enabled (10 pts)
    # Status 1 = Enabled
    if str(product.get('status')) == '1':
        score += 10
        feedback_parts.append("Status enabled")
    else:
        feedback_parts.append("Status not enabled")

    # Criterion 4: Visibility Catalog, Search (5 pts)
    # Visibility 4 = Catalog, Search
    if str(product.get('visibility')) == '4':
        score += 5
        feedback_parts.append("Visibility correct")
    else:
        feedback_parts.append("Visibility incorrect")

    # Criterion 5: Category is Sports (10 pts)
    actual_category = product.get('category', '')
    if expected_category.lower() in actual_category.lower():
        score += 10
        feedback_parts.append("Category correct")
    else:
        feedback_parts.append(f"Category mismatch: expected {expected_category}, got {actual_category}")

    # Criterion 6, 7, 8: Child Products (30 pts total)
    linked_skus = [s.lower().strip() for s in product.get('linked_skus', [])]
    
    required_children = ['YOGA-001', 'BOTTLE-001', 'TSHIRT-001']
    for child in required_children:
        if child.lower() in linked_skus:
            score += 10
            feedback_parts.append(f"Child {child} linked")
        else:
            feedback_parts.append(f"Child {child} MISSING")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }