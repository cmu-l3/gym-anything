#!/usr/bin/env python3
"""Verifier for Downloadable Product task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_downloadable_product(traj, env_info, task_info):
    """
    Verify creation of a downloadable product with specific links.
    
    Criteria:
    1. Product exists with correct SKU (10 pts)
    2. Product type is 'downloadable' (15 pts)
    3. Product Name matches (10 pts)
    4. Product Price is 14.99 (10 pts)
    5. 'Links purchased separately' is enabled (5 pts)
    6. At least 1 link exists (20 pts)
    7. Exactly 2 links exist (10 pts)
    8. Link details (Title, Price, Downloads) match specific requirements (20 pts split)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sku = metadata.get('expected_sku', 'DWAC-VOL1')
    expected_name = metadata.get('expected_name', 'Digital Watercolor Collection Vol. 1')
    expected_price = float(metadata.get('expected_price', 14.99))
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/downloadable_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    logger.info(f"Result data: {result}")

    score = 0
    feedback_parts = []
    
    product_found = result.get('product_found', False)
    product = result.get('product', {})
    
    # 1. Product exists (10 pts)
    if product_found:
        score += 10
        feedback_parts.append("Product found")
    else:
        return {"passed": False, "score": 0, "feedback": f"Product with SKU {expected_sku} not found"}

    # 2. Product type (15 pts) - CRITICAL
    p_type = product.get('type', '')
    if p_type == 'downloadable':
        score += 15
        feedback_parts.append("Type is downloadable")
    else:
        feedback_parts.append(f"Type mismatch: expected 'downloadable', got '{p_type}'")

    # 3. Product Name (10 pts)
    p_name = product.get('name', '')
    if expected_name.lower() in p_name.lower():
        score += 10
        feedback_parts.append("Name matches")
    else:
        feedback_parts.append(f"Name mismatch: got '{p_name}'")

    # 4. Product Price (10 pts)
    try:
        p_price = float(product.get('price', 0))
        if abs(p_price - expected_price) < 0.01:
            score += 10
            feedback_parts.append("Price correct")
        else:
            feedback_parts.append(f"Price mismatch: got {p_price}, expected {expected_price}")
    except:
        feedback_parts.append("Price invalid")

    # 5. Links purchased separately (5 pts)
    # Value is usually "1" for Yes
    links_sep = str(product.get('links_purchased_separately', '0')).strip()
    if links_sep == '1':
        score += 5
        feedback_parts.append("Links configurable separately")
    else:
        feedback_parts.append("Links not set to purchase separately")

    # Links verification
    links = product.get('links', [])
    num_links = len(links)
    
    # 6. At least 1 link (20 pts)
    if num_links >= 1:
        score += 20
        feedback_parts.append("Downloadable links found")
    else:
        feedback_parts.append("No downloadable links found")

    # 7. Exactly 2 links (10 pts)
    if num_links == 2:
        score += 10
        feedback_parts.append("Count of links correct (2)")
    elif num_links > 0:
        feedback_parts.append(f"Count of links mismatch: got {num_links}, expected 2")

    # 8. Link details (20 pts max)
    # We look for specific keywords in titles
    link_score = 0
    full_collection_found = False
    sample_pack_found = False
    
    for link in links:
        title = link.get('title', '').lower()
        price = float(link.get('price', 0))
        downloads = int(link.get('downloads', 0))
        
        if "full collection" in title:
            # Check Full Collection details
            if abs(price - 0.0) < 0.01 and downloads == 5:
                link_score += 10
                full_collection_found = True
            elif abs(price - 0.0) < 0.01:
                 # Price right, downloads wrong
                 link_score += 5
        
        elif "sample pack" in title:
            # Check Sample Pack details
            if abs(price - 4.99) < 0.01 and downloads == 3:
                link_score += 10
                sample_pack_found = True
            elif abs(price - 4.99) < 0.01:
                link_score += 5

    score += link_score
    if full_collection_found and sample_pack_found:
        feedback_parts.append("All link details correct")
    elif link_score > 0:
        feedback_parts.append(f"Partial link details correct (+{link_score} pts)")
    else:
        feedback_parts.append("Link details incorrect")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }