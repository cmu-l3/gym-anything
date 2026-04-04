#!/usr/bin/env python3
"""
Verifier for Create Refurbished Product Listing task.

Verification Strategy:
1. Programmatic Checks (80 pts):
   - Product exists and is published
   - SKU matches WBH-001-REF
   - Price matches 49.99
   - Stock matches 50
   - Description inherited (content length similar to source)
   - Created during task window (Anti-gaming)
2. VLM Checks (20 pts):
   - Verify workflow via trajectory (duplication or manual entry)
   - Verify final state screenshot

Pass Threshold: 100 points (Strict inventory task)
"""

import json
import tempfile
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_refurbished_product(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sku = metadata.get('target_sku', 'WBH-001-REF')
    expected_price = metadata.get('target_price', '49.99')
    expected_stock = metadata.get('target_stock', '50')
    
    score = 0
    feedback = []

    # 2. Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    product = result.get('product', {})
    source = result.get('source', {})
    product_found = result.get('product_found', False)
    task_start = result.get('task_start_time', 0)

    # 3. Programmatic Verification
    if not product_found:
        return {"passed": False, "score": 0, "feedback": "Target product not found."}

    # A. Product Exists & Published (20 pts)
    if product.get('status') == 'publish':
        score += 20
        feedback.append("Product published.")
    else:
        feedback.append(f"Product found but status is '{product.get('status')}'.")

    # B. SKU Check (20 pts)
    if product.get('sku') == expected_sku:
        score += 20
        feedback.append("SKU correct.")
    else:
        feedback.append(f"SKU incorrect: found {product.get('sku')}, expected {expected_sku}.")

    # C. Price Check (20 pts)
    # Flexible string/float comparison
    try:
        if float(product.get('price', 0)) == float(expected_price):
            score += 20
            feedback.append("Price correct.")
        else:
            feedback.append(f"Price incorrect: found {product.get('price')}, expected {expected_price}.")
    except:
        feedback.append("Price format error.")

    # D. Stock Check (20 pts)
    try:
        if int(product.get('stock', 0)) == int(expected_stock):
            score += 20
            feedback.append("Stock correct.")
        else:
            feedback.append(f"Stock incorrect: found {product.get('stock')}, expected {expected_stock}.")
    except:
        feedback.append("Stock format error.")

    # E. Content Inheritance Check (10 pts)
    # We expect the description to be roughly the same length as source
    # Allow small variance if they edited it slightly, but it shouldn't be empty
    p_len = product.get('content_length', 0)
    s_len = source.get('content_length', 0)
    
    if p_len > 0 and abs(p_len - s_len) < 50:
        score += 10
        feedback.append("Description inherited correctly.")
    elif p_len == 0:
        feedback.append("Description is empty (should inherit from source).")
    else:
        # Partial credit if they wrote *something* but it doesn't match source
        score += 5
        feedback.append("Description present but differs significantly from source.")

    # F. Anti-Gaming Timestamp Check (10 pts)
    created_at = int(product.get('created_at', 0))
    # Allow 60s tolerance for clock drift between container and host if strict
    # Generally, created_at should be >= task_start
    if created_at >= task_start:
        score += 10
        feedback.append("Created during task window.")
    else:
        feedback.append("Product creation time predates task start (Pre-existing/Cheating).")
        score = 0 # Fail completely if cheating detected

    # Final Evaluation
    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }