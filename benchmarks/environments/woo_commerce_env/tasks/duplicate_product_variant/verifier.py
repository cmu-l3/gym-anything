#!/usr/bin/env python3
"""
Verifier for Duplicate Product Variant task.

Scoring Criteria (100 points total):
1. Product Exists & SKU Correct (20 pts)
2. Title Matches (15 pts)
3. Price Updated to 129.99 (15 pts)
4. Status is Published (15 pts)
5. Visibility is 'Search results only' (20 pts)
6. Description Preserved (Evidence of Duplication) (15 pts)

Bonus/Penalty:
- Must be a NEW product (created during task).
- If visibility is wrong, partial points depending on state.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_duplicate_product_variant(traj, env_info, task_info):
    """
    Verify creation of the Gold Edition product via duplication.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sku = metadata.get('expected_sku', 'WBH-001-GOLD')
    expected_name = metadata.get('expected_name', 'Wireless Bluetooth Headphones - Gold Edition')
    expected_price = metadata.get('expected_price', '129.99')
    
    # Load result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    product_found = result.get('product_found', False)
    product_data = result.get('product', {})
    
    if not product_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Product with SKU {expected_sku} not found."
        }

    # 1. Product Found & New (20 pts)
    score += 15
    feedback.append("Product found by SKU.")
    
    if product_data.get('is_new', False):
        score += 5
        feedback.append("Product created during task.")
    else:
        feedback.append("WARNING: Product timestamp predates task start (reused?).")

    # 2. Title Match (15 pts)
    actual_title = product_data.get('title', '').strip()
    if actual_title == expected_name:
        score += 15
        feedback.append("Title correct.")
    else:
        feedback.append(f"Title mismatch: '{actual_title}' vs '{expected_name}'")

    # 3. Price Match (15 pts)
    actual_price = product_data.get('price', '')
    # Handle float formatting differences (129.9900 vs 129.99)
    try:
        if float(actual_price) == float(expected_price):
            score += 15
            feedback.append("Price correct.")
        else:
            feedback.append(f"Price mismatch: {actual_price} vs {expected_price}")
    except:
        feedback.append(f"Invalid price format: {actual_price}")

    # 4. Status Published (15 pts)
    status = product_data.get('status', 'unknown')
    if status == 'publish':
        score += 15
        feedback.append("Product is published.")
    else:
        feedback.append(f"Status incorrect: {status}")

    # 5. Visibility (20 pts)
    # Expected: "Search results only" -> term 'exclude-from-catalog' present, 'exclude-from-search' NOT present
    visibility_terms = product_data.get('visibility_terms', [])
    
    has_exclude_catalog = 'exclude-from-catalog' in visibility_terms
    has_exclude_search = 'exclude-from-search' in visibility_terms
    
    if has_exclude_catalog and not has_exclude_search:
        score += 20
        feedback.append("Visibility set to 'Search results only'.")
    elif has_exclude_catalog and has_exclude_search:
        # This is "Hidden"
        score += 5
        feedback.append("Visibility set to 'Hidden' (expected 'Search results only').")
    elif not has_exclude_catalog and not has_exclude_search:
        # This is "Shop and search results" (default)
        feedback.append("Visibility left as Default (expected 'Search results only').")
    elif not has_exclude_catalog and has_exclude_search:
        # This is "Shop only"
        feedback.append("Visibility set to 'Shop only' (expected 'Search results only').")

    # 6. Description Check (15 pts)
    # This verifies duplication was used (or text manually copied perfectly)
    actual_desc = product_data.get('description', '').strip()
    source_desc = result.get('source_description', '').strip()
    
    # Calculate simple Jaccard similarity or direct equality
    # Since it's a duplication, it should be identical
    if actual_desc and source_desc and actual_desc == source_desc:
        score += 15
        feedback.append("Description preserved (duplication verified).")
    elif actual_desc and source_desc:
        # Allow slight edits? Task didn't ask for edits.
        # Check if length is similar (>90%)
        if len(actual_desc) > 0 and abs(len(actual_desc) - len(source_desc)) < 20:
             score += 10
             feedback.append("Description mostly preserved.")
        else:
             feedback.append("Description differs significantly from source.")
    else:
        feedback.append("Description empty or missing.")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }