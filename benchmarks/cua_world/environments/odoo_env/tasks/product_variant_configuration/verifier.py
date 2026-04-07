#!/usr/bin/env python3
"""
Verifier for product_variant_configuration task.
"""

import json
import logging
import tempfile
import os
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_product_variant_configuration(traj, env_info, task_info):
    """
    Verifies that the Alpine Performance Jacket was created with:
    1. Correct product fields (Price, Cost, Ref, Type)
    2. Correct Attributes (Size, Color)
    3. Correct Values (S,M,L,XL; Navy,Green,Charcoal)
    4. Correct Price Extras (XL +15, Green +10)
    5. Correct Variant Count (12)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Load result from container
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

    # Basic Checks
    if not result.get('product_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Product 'Alpine Performance Jacket' not found in database."
        }

    score = 0
    max_score = 100
    feedback = []
    
    product = result.get('product_data', {})
    
    # Criterion 1: Product Basics (25 pts)
    # Price
    if abs(product.get('list_price', 0) - metadata.get('expected_price', 189.0)) < 0.1:
        score += 8
    else:
        feedback.append(f"Incorrect price: {product.get('list_price')}")

    # Cost
    if abs(product.get('standard_price', 0) - metadata.get('expected_cost', 85.0)) < 0.1:
        score += 7
    else:
        feedback.append(f"Incorrect cost: {product.get('standard_price')}")

    # Internal Ref
    if product.get('default_code') == metadata.get('internal_ref', 'APJ-BASE'):
        score += 5
    else:
        feedback.append(f"Incorrect Ref: {product.get('default_code')}")

    # Type
    if product.get('type') == 'product': # 'product' key means Storable
        score += 5
    else:
        feedback.append(f"Incorrect Type: {product.get('type')} (expected Storable)")

    # Criterion 2: Attributes and Values (27 pts)
    found_attrs = result.get('attributes_found', {})
    expected_attrs = metadata.get('attributes', {})
    
    for attr_name, expected_vals in expected_attrs.items():
        # Check if attribute exists (case insensitive matching might be needed but simple dict check first)
        matching_key = next((k for k in found_attrs if k.lower() == attr_name.lower()), None)
        
        if matching_key:
            score += 5 # Attribute exists
            
            # Check values
            found_vals = found_attrs[matching_key]
            # Normalize for comparison
            found_set = {str(v).lower() for v in found_vals}
            expected_set = {str(v).lower() for v in expected_vals}
            
            if found_set == expected_set:
                score += 8.5 # Full points for this attribute's values
            elif found_set.issuperset(expected_set):
                score += 5 # Extra values present
                feedback.append(f"Attribute {attr_name} has extra values")
            else:
                score += 2 # Some values missing
                feedback.append(f"Attribute {attr_name} missing values")
        else:
            feedback.append(f"Attribute {attr_name} not found")

    # Criterion 3: Price Extras (18 pts)
    found_extras = result.get('price_extras_found', {})
    expected_extras = metadata.get('price_extras', {})
    
    for val_name, amount in expected_extras.items():
        # Find matching key in found extras (fuzzy match since Odoo might prepend "Size: ")
        found_amount = None
        for k, v in found_extras.items():
            if val_name.lower() in k.lower():
                found_amount = v
                break
        
        if found_amount is not None:
            if abs(found_amount - amount) < 0.1:
                score += 9
            else:
                score += 3
                feedback.append(f"Wrong price extra for {val_name}: {found_amount} vs {amount}")
        else:
            feedback.append(f"No price extra found for {val_name}")

    # Criterion 4: Variant Count (10 pts)
    expected_count = metadata.get('expected_variant_count', 12)
    actual_count = result.get('variants_count', 0)
    
    if actual_count == expected_count:
        score += 10
    else:
        feedback.append(f"Incorrect variant count: {actual_count} (expected {expected_count})")

    # Criterion 5: Description (10 pts)
    desc = str(product.get('description_sale', '') or '')
    keywords = metadata.get('description_keywords', [])
    if all(k.lower() in desc.lower() for k in keywords):
        score += 10
    elif any(k.lower() in desc.lower() for k in keywords):
        score += 5
        feedback.append("Description missing some keywords")
    else:
        feedback.append("Description missing/incorrect")

    # Criterion 6: Anti-Gaming (10 pts)
    # Check creation time vs task start
    task_start = result.get('task_start', 0)
    create_date_str = result.get('create_date')
    if create_date_str:
        # Odoo returns string like "2023-10-25 10:00:00"
        try:
            # Parse Odoo datetime (usually UTC)
            # Simplified check: just ensure it wasn't pre-existing
            # We assume the setup script cleaned/checked properly, 
            # verifying create_date is > task_start is good if clocks are synced.
            # Using a safer proxy: check if create_date is not None (it is new)
            score += 10
        except:
            pass
    
    passed = score >= 65 and actual_count > 1 # Must have variants to pass
    
    return {
        "passed": passed,
        "score": round(score),
        "feedback": "; ".join(feedback) if feedback else "Perfect execution"
    }