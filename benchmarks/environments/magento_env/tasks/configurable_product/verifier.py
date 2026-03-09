#!/usr/bin/env python3
"""Verifier for Configurable Product task in Magento.

Task: Create attribute 'shirt_color' (White, Blue, Black), then create
Configurable Product 'Oxford Dress Shirt' (SHIRT-OXFORD-001) with 3 variants.

Scored on 5 criteria (100 pts). Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configurable_product(traj, env_info, task_info):
    """
    Verify creation of configurable product and its attribute.
    
    Criteria:
    1. Attribute 'shirt_color' exists and is dropdown (15 pts)
    2. Attribute has correct options (White, Blue, Black) (15 pts)
    3. Configurable Product exists with correct SKU and Type (20 pts)
    4. Product details correct (Name, Price, Category) (30 pts)
    5. Product has at least 3 associated variants (20 pts)
    
    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/config_prod_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, 
                "feedback": "Result file not found — export_result.sh may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # 1. Attribute Existence (15 pts)
    attr_found = result.get('attribute_found', False)
    attr_input = result.get('attribute_input', '')
    
    if attr_found:
        if attr_input == 'select':
            score += 15
            feedback_parts.append("Attribute 'shirt_color' created correctly (dropdown) (15 pts)")
        else:
            score += 10
            feedback_parts.append(f"Attribute created but wrong input type: {attr_input} (expected 'select') (10 pts)")
    else:
        feedback_parts.append("Attribute 'shirt_color' NOT found")

    # 2. Attribute Options (15 pts)
    options_count = result.get('options_found_count', 0)
    # expected 3: White, Blue, Black
    if options_count >= 3:
        score += 15
        feedback_parts.append("All 3 color options found (15 pts)")
    elif options_count > 0:
        partial = options_count * 5
        score += partial
        feedback_parts.append(f"Partial options found ({options_count}/3) ({partial} pts)")
    else:
        feedback_parts.append("No correct attribute options found")

    # 3. Configurable Product Existence (20 pts)
    prod_found = result.get('product_found', False)
    prod_type = result.get('product_type', '')
    
    if prod_found:
        if prod_type == 'configurable':
            score += 20
            feedback_parts.append("Configurable Product created (20 pts)")
        else:
            score += 10
            feedback_parts.append(f"Product created but wrong type: {prod_type} (expected 'configurable') (10 pts)")
    else:
        feedback_parts.append("Product 'SHIRT-OXFORD-001' NOT found")

    # 4. Product Details (30 pts)
    # Name (10), Price (10), Category (10)
    if prod_found:
        # Name
        name = result.get('product_name', '')
        if 'oxford dress shirt' in name.lower():
            score += 10
            feedback_parts.append("Name correct (10 pts)")
        else:
            feedback_parts.append(f"Name mismatch: '{name}'")
            
        # Price
        try:
            price = float(result.get('product_price', 0))
            if abs(price - 59.99) < 0.1:
                score += 10
                feedback_parts.append("Price correct (10 pts)")
            else:
                feedback_parts.append(f"Price mismatch: {price}")
        except:
            feedback_parts.append("Price invalid")
            
        # Category
        cat = result.get('product_category', '')
        if 'Clothing' in cat:
            score += 10
            feedback_parts.append("Category correct (10 pts)")
        else:
            feedback_parts.append("Category mismatch or not assigned")

    # 5. Variants Linked (20 pts)
    variants = result.get('variant_count', 0)
    if variants >= 3:
        score += 20
        feedback_parts.append(f"Variants linked correctly ({variants}) (20 pts)")
    elif variants > 0:
        partial = min(variants * 6, 15)
        score += partial
        feedback_parts.append(f"Partial variants linked ({variants}) ({partial} pts)")
    else:
        feedback_parts.append("No simple product variants linked to configurable product")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }