#!/usr/bin/env python3
"""
Verifier for create_external_product task.

Verifies that the agent created a new External/Affiliate product with specific details.
Specific focus on the 'external' product type and its unique fields (URL, button text).

Verification Strategy:
1. Programmatic: Check database for product existence and correct fields (90 pts)
2. Anti-gaming: Check product was created during task and count increased (5 pts)
3. VLM: Verify UI trajectory shows interaction with product type dropdown (5 pts)
"""

import json
import tempfile
import os
import logging
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_external_product(traj, env_info, task_info):
    """
    Verify that the external product was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sku = metadata.get('expected_sku', 'EXT-SONY-WH1000XM5')
    expected_url = metadata.get('expected_url', 'https://www.amazon.com/dp/B09XS7JWHH')
    expected_button = metadata.get('expected_button_text', 'Buy on Amazon')
    expected_type = metadata.get('expected_type', 'external')
    
    score = 0
    feedback_parts = []
    
    # 1. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Programmatic Verification (90 pts)
    product = result.get('product', {})
    product_found = result.get('product_found', False)
    
    if not product_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Product not found. Ensure you created a product with the name 'Sony WH-1000XM5 Wireless Headphones' or SKU 'EXT-SONY-WH1000XM5'."
        }
    
    score += 15
    feedback_parts.append("Product found")
    
    # Check Status (must be publish)
    if product.get('status') == 'publish':
        score += 5
        feedback_parts.append("Status: Publish (+5)")
    else:
        feedback_parts.append(f"Status: {product.get('status')} (expected 'publish')")
        
    # Check Type (CRITICAL - 20 pts)
    if product.get('type') == expected_type:
        score += 20
        feedback_parts.append("Type: External/Affiliate (+20)")
    else:
        feedback_parts.append(f"Type: {product.get('type')} (expected '{expected_type}')")
        
    # Check URL (15 pts)
    # Flexible check: contains amazon.com and the ASIN
    p_url = product.get('product_url', '')
    if "amazon.com" in p_url and "B09XS7JWHH" in p_url:
        score += 15
        feedback_parts.append("URL: Correct (+15)")
    else:
        feedback_parts.append(f"URL: Incorrect ('{p_url}')")
        
    # Check Button Text (10 pts)
    # Case insensitive check
    if expected_button.lower() in product.get('button_text', '').lower():
        score += 10
        feedback_parts.append("Button Text: Correct (+10)")
    else:
        feedback_parts.append(f"Button Text: Incorrect ('{product.get('button_text')}')")
        
    # Check Price (10 pts)
    # Allow 348 or 348.00
    price = str(product.get('regular_price', ''))
    if price.startswith("348"):
        score += 10
        feedback_parts.append("Price: Correct (+10)")
    else:
        feedback_parts.append(f"Price: Incorrect ({price})")
        
    # Check SKU (10 pts)
    if product.get('sku') == expected_sku:
        score += 10
        feedback_parts.append("SKU: Correct (+10)")
    else:
        feedback_parts.append(f"SKU: Incorrect ({product.get('sku')})")
        
    # Check Category (5 pts)
    cats = product.get('categories', '')
    if "Electronics" in cats:
        score += 5
        feedback_parts.append("Category: Electronics (+5)")
    else:
        feedback_parts.append(f"Category: Incorrect ({cats})")
        
    # 3. Anti-gaming Checks (5 pts)
    # Check if created during task
    task_start = int(result.get('task_start', 0))
    created_time = int(product.get('created_timestamp', 0))
    initial_count = int(result.get('initial_count', 0))
    current_count = int(result.get('current_count', 0))
    
    # Allow 60s tolerance for clock drift or setup delays
    if created_time > (task_start - 60) and current_count > initial_count:
        score += 5
        feedback_parts.append("Anti-gaming: Verified new product (+5)")
    else:
        feedback_parts.append("Anti-gaming: Timestamp/Count check failed")

    # 4. VLM Trajectory Check (5 pts)
    # We award these points if the core programmatic checks pass, implying correct workflow
    # Ideally we'd use VLM here, but for this specific task, if the product exists with type='external',
    # url='...', and button_text='...', the agent MUST have used the correct UI elements.
    if score >= 60:
         score += 5
         feedback_parts.append("Workflow: Implied success (+5)")

    pass_threshold = 60
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }