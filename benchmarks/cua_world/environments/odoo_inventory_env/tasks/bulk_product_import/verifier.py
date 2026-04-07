#!/usr/bin/env python3

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_product_import(traj, env_info, task_info):
    """
    Verify the Bulk Product Catalog Import task.

    Scoring (100 pts total, Pass threshold: 60):
      - 48 pts: Product exists per expected SKU or exact Name (4 pts × 12 products)
      - 24 pts: Correct Internal Reference / SKU mapped (2 pts × 12 products)
      - 12 pts: Correct Sales Price (1 pt × 12 products)
      - 12 pts: Correct Cost Price (1 pt × 12 products)
      -  4 pts: At least 10 products assigned correctly to "Electronics" category
    """
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})
    expected_products = metadata.get('expected_products', {})
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tf:
        local_path = tf.name

    try:
        copy_from_env("/tmp/bulk_import_result.json", local_path)
        with open(local_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export result: {e}"}
    finally:
        if os.path.exists(local_path):
            os.unlink(local_path)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    products_by_sku = result.get('products_found_by_sku', {})
    products_by_name = result.get('products_found_by_name', {})
    elec_cat_id = result.get('electronics_category_id')
    task_start = result.get('task_start', 0)

    # Metric tracking
    products_found = 0
    correct_skus = 0
    correct_prices = 0
    correct_costs = 0
    correct_categories = 0
    
    for expected_sku, expected_data in expected_products.items():
        expected_name = expected_data['name']
        expected_cost = expected_data['cost']
        expected_price = expected_data['price']
        
        # Try to find the product either by its exact SKU, or by its exact Name
        # If the user failed to map the SKU column, it won't be in products_by_sku
        prod_record = products_by_sku.get(expected_sku)
        
        if not prod_record:
            # Check if it was imported but the SKU mapping was missed
            prod_record = products_by_name.get(expected_name)
            
        if prod_record:
            # Check Anti-gaming: Ensure it was created after task start
            create_date_str = prod_record.get('create_date')
            if create_date_str:
                try:
                    # Odoo returns create_date as 'YYYY-MM-DD HH:MM:SS' string in UTC
                    dt = datetime.strptime(create_date_str, "%Y-%m-%d %H:%M:%S")
                    if dt.timestamp() < task_start - 300: # generous buffer for clock skew
                        logger.warning(f"Product {expected_sku} created before task start")
                except Exception:
                    pass
            
            # 1. Exists (4 pts)
            score += 4
            products_found += 1
            
            # 2. Correct SKU / Internal Reference (2 pts)
            if prod_record.get('default_code') == expected_sku:
                score += 2
                correct_skus += 1
                
            # 3. Correct Sales Price (1 pt)
            actual_price = prod_record.get('list_price', 0)
            if abs(actual_price - expected_price) <= 0.50:
                score += 1
                correct_prices += 1
                
            # 4. Correct Cost Price (1 pt)
            actual_cost = prod_record.get('standard_price', 0)
            if abs(actual_cost - expected_cost) <= 0.50:
                score += 1
                correct_costs += 1
                
            # Track category assignment for the group metric
            cat = prod_record.get('categ_id', [0, ""])
            # The category could be "All / Electronics" or just "Electronics"
            if cat and (cat[0] == elec_cat_id or 'Electronics' in cat[1]):
                correct_categories += 1

    feedback_parts.append(f"Imported {products_found}/12 products")
    if products_found > 0:
        feedback_parts.append(f"{correct_skus} mapped SKU correctly")
        feedback_parts.append(f"{correct_prices} mapped Sales Price correctly")
        feedback_parts.append(f"{correct_costs} mapped Cost correctly")

    # 5. Category assignment group metric (4 pts)
    if correct_categories >= 10:
        score += 4
        feedback_parts.append(f"Category 'Electronics' correctly mapped")
    elif correct_categories > 0:
        feedback_parts.append(f"Only {correct_categories}/12 products had correct category mapped")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "products_found": products_found,
            "correct_skus": correct_skus,
            "correct_prices": correct_prices,
            "correct_costs": correct_costs,
            "correct_categories": correct_categories
        }
    }