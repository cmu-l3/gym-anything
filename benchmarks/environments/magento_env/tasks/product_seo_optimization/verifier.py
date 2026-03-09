#!/usr/bin/env python3
"""Verifier for Product SEO Optimization task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_product_seo_optimization(traj, env_info, task_info):
    """
    Verify Product SEO updates.
    
    Criteria:
    1. URL Key matches 'business-laptop-pro-2025' (30 pts)
    2. Meta Title matches exact text (25 pts)
    3. Meta Description matches exact text (25 pts)
    4. 301 Redirect exists for the new URL key (20 pts)
    
    Pass threshold: 80 pts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Expected values
    metadata = task_info.get('metadata', {})
    exp_url_key = metadata.get('expected_url_key', 'business-laptop-pro-2025')
    exp_meta_title = metadata.get('expected_meta_title', 'Business Laptop Pro 15-inch | Enterprise Edition')
    exp_meta_desc = metadata.get('expected_meta_description', 'Upgrade your workflow with the Business Laptop Pro. Featuring 16GB RAM, 512GB SSD, and all-day battery life. Free shipping on orders over $500.')

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/product_seo_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check if product was found
    if not result.get('product_found', False):
        return {"passed": False, "score": 0, "feedback": "Product not found in database."}

    score = 0
    feedback_parts = []
    
    # 1. Check URL Key (30 pts)
    act_url_key = result.get('current_url_key', '').strip()
    if act_url_key == exp_url_key:
        score += 30
        feedback_parts.append("URL Key updated correctly")
    else:
        feedback_parts.append(f"URL Key mismatch: expected '{exp_url_key}', got '{act_url_key}'")

    # 2. Check Meta Title (25 pts)
    act_meta_title = result.get('current_meta_title', '').strip()
    if act_meta_title == exp_meta_title:
        score += 25
        feedback_parts.append("Meta Title updated correctly")
    else:
        feedback_parts.append(f"Meta Title mismatch: got '{act_meta_title}'")

    # 3. Check Meta Description (25 pts)
    act_meta_desc = result.get('current_meta_description', '').strip()
    if act_meta_desc == exp_meta_desc:
        score += 25
        feedback_parts.append("Meta Description updated correctly")
    else:
        # Allow slight whitespace diffs
        if act_meta_desc.replace(" ", "") == exp_meta_desc.replace(" ", ""):
            score += 25
            feedback_parts.append("Meta Description updated correctly (ignoring whitespace)")
        else:
            feedback_parts.append(f"Meta Description mismatch")

    # 4. Check Redirect (20 pts)
    redirect_found = result.get('redirect_found', False)
    
    # If URL key wasn't changed from initial, redirect point is moot, 
    # but technically if they didn't change URL key, they shouldn't get points for redirect either.
    initial_key = result.get('initial_url_key', '')
    if act_url_key == initial_key and act_url_key != exp_url_key:
        # URL key didn't change, so no redirect expected/generated usually
        pass
    elif redirect_found:
        score += 20
        feedback_parts.append("Permanent Redirect created")
    else:
        feedback_parts.append("Permanent Redirect NOT found (checkbox likely missed)")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }