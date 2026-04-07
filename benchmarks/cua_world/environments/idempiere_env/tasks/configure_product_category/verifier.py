#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_product_category(traj, env_info, task_info):
    """
    Verifies that:
    1. A Product Category with key 'OUTDOOR-FURN' exists and has correct settings.
    2. The product 'Patio Chair' is assigned to this new category.
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

    # Extract data
    category = result.get('category_record')
    product = result.get('product_record')
    initial_cat_id = result.get('initial_product_cat_id', '0')
    task_start_time = result.get('task_start_time', 0)

    score = 0
    feedback = []
    
    # ---------------------------------------------------------
    # Criterion 1: Product Category Created (Max 50 pts)
    # ---------------------------------------------------------
    if category:
        score += 20
        feedback.append("Product Category 'OUTDOOR-FURN' created.")
        
        # Check Name
        if category.get('name') == 'Outdoor Furniture':
            score += 10
        else:
            feedback.append(f"Incorrect Category Name: {category.get('name')}")

        # Check Material Policy (FiFo = 'F')
        if category.get('mmpolicy') == 'F':
            score += 15
        else:
            feedback.append(f"Incorrect Material Policy: {category.get('mmpolicy')} (Expected FiFo)")

        # Check Margin
        # DB might return float or int
        margin = float(category.get('plannedmargin', 0))
        if abs(margin - 20.0) < 0.1:
            score += 5
        else:
            feedback.append(f"Incorrect Planned Margin: {margin} (Expected 20)")
            
        # Anti-gaming: Timestamp check
        # iDempiere stores timestamps. Depending on DB timezone, this can be tricky, 
        # but if the record didn't exist before (checked in setup), existence is strong evidence.
    else:
        feedback.append("Product Category 'OUTDOOR-FURN' NOT found.")

    # ---------------------------------------------------------
    # Criterion 2: Product Reclassified (Max 50 pts)
    # ---------------------------------------------------------
    if product and category:
        current_cat_id = str(product.get('m_product_category_id', ''))
        new_cat_id = str(category.get('m_product_category_id', ''))
        
        if current_cat_id == new_cat_id:
            score += 30
            feedback.append("Product 'Patio Chair' successfully moved to new category.")
        else:
            feedback.append("Product 'Patio Chair' is not assigned to the new category.")
            
        # Check if it actually changed
        if current_cat_id != str(initial_cat_id):
            score += 20
            feedback.append("Product category was modified.")
        else:
            feedback.append("Product category was NOT changed from initial state.")
    elif not product:
        feedback.append("Product 'Patio Chair' NOT found in database (Critical Error).")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    # Threshold: Need Category Created (approx 50) + Product Moved (30) = 80 to be decent
    # Minimum pass: 70
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }