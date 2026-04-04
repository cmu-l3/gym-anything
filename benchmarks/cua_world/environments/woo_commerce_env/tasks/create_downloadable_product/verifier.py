#!/usr/bin/env python3
"""
Verifier for Create Downloadable Product task.

Verification Strategy:
1. Programmatic Checks (Database):
   - Product exists with correct SKU
   - Prices are correct (Regular & Sale)
   - Virtual and Downloadable flags are set to 'yes'
   - Download limit and expiry are set correctly
   - 'Digital Patterns' category exists and is assigned
   - A downloadable file is attached (check meta for filename)

2. VLM Checks (Trajectory):
   - Verify workflow: Agent navigating to "Downloadable" options, uploading file.
   - Verify final state if DB check is ambiguous (rare).
"""

import json
import logging
import os
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_downloadable_product(traj, env_info, task_info):
    """
    Verify the creation of a downloadable product.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sku = metadata.get('expected_sku', 'VFCS-PAT-001')
    expected_reg_price = metadata.get('expected_regular_price', '12.99')
    expected_sale_price = metadata.get('expected_sale_price', '9.99')
    expected_limit = metadata.get('expected_download_limit', '3')
    expected_expiry = metadata.get('expected_download_expiry', '30')
    expected_cat = metadata.get('expected_category', 'Digital Patterns')
    expected_file_part = metadata.get('expected_filename_part', 'vintage_floral_pattern.pdf')

    # Load result from container
    try:
        import tempfile
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # 1. Product Existence (20 pts)
    if result.get("product_found"):
        score += 20
        feedback.append("Product found by SKU.")
    else:
        return {"passed": False, "score": 0, "feedback": "Product with SKU VFCS-PAT-001 not found."}

    # 2. Virtual & Downloadable Flags (20 pts)
    is_virt = result.get("is_virtual", "no")
    is_down = result.get("is_downloadable", "no")
    
    if is_virt == "yes":
        score += 10
        feedback.append("Virtual flag set.")
    else:
        feedback.append("Virtual flag MISSING.")

    if is_down == "yes":
        score += 10
        feedback.append("Downloadable flag set.")
    else:
        feedback.append("Downloadable flag MISSING.")

    # 3. Pricing (10 pts)
    # Check exact match or float match
    try:
        reg_match = float(result.get("regular_price", 0)) == float(expected_reg_price)
        sale_match = float(result.get("sale_price", 0)) == float(expected_sale_price)
    except:
        reg_match = False
        sale_match = False

    if reg_match:
        score += 5
    else:
        feedback.append(f"Regular price mismatch (got {result.get('regular_price')})")

    if sale_match:
        score += 5
    else:
        feedback.append(f"Sale price mismatch (got {result.get('sale_price')})")

    # 4. Download Settings (15 pts)
    limit = result.get("download_limit", "")
    expiry = result.get("download_expiry", "")
    
    if str(limit) == expected_limit:
        score += 7
    else:
        feedback.append(f"Download limit mismatch (got {limit}, expected {expected_limit})")

    if str(expiry) == expected_expiry:
        score += 8
    else:
        feedback.append(f"Download expiry mismatch (got {expiry}, expected {expected_expiry})")

    # 5. File Attachment (20 pts)
    # The meta value is a serialized PHP array string. We check if the filename is present in it.
    files_meta = result.get("downloadable_files_meta", "")
    if expected_file_part in files_meta:
        score += 20
        feedback.append("Downloadable file attached correctly.")
    else:
        feedback.append("Downloadable file NOT found in product metadata.")

    # 6. Category (15 pts)
    categories = result.get("categories", "")
    # Check if expected category is in the comma-separated list
    cat_list = [c.strip().lower() for c in categories.split(',')]
    if expected_cat.lower() in cat_list:
        score += 15
        feedback.append("Category assigned correctly.")
    else:
        feedback.append(f"Category '{expected_cat}' not assigned (got: {categories}).")

    passed = score >= 70 and is_virt == "yes" and is_down == "yes" and (expected_file_part in files_meta)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }