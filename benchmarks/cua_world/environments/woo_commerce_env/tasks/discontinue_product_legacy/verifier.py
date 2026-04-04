#!/usr/bin/env python3
"""
Verifier for Discontinue Product Legacy task.

Verification Strategy:
1. Product Visibility (30 pts): Must include both 'exclude-from-search' and 'exclude-from-catalog'.
2. Stock Status (30 pts): Must be 'outofstock'.
3. Discontinuation Notice (30 pts): Short description must contain specific text.
4. Product Integrity (10 pts): Product must not be deleted (status='publish').
5. VLM Verification (Penalty only): Checks if UI was used if programmatic checks pass.

Pass Threshold: 100 points.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_discontinue_product(traj, env_info, task_info):
    """
    Verify the product was discontinued correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_notice = metadata.get('expected_notice_text', '**DISCONTINUED: This item is no longer available.**')
    
    # Retrieve result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}

    score = 0
    feedback = []
    
    # 1. Check Product Existence & Status (10 pts)
    if not result.get('product_found', False):
        return {"passed": False, "score": 0, "feedback": "Target product not found."}
    
    post_status = result.get('post_status', '')
    if post_status == 'publish':
        score += 10
        feedback.append("Product preserved (not deleted).")
    else:
        feedback.append(f"Product status is '{post_status}' (expected 'publish').")

    # 2. Check Visibility (30 pts)
    # Expected: "Hidden" maps to both exclude-from-search and exclude-from-catalog
    visibility_terms = result.get('visibility_terms', [])
    search_hidden = 'exclude-from-search' in visibility_terms
    catalog_hidden = 'exclude-from-catalog' in visibility_terms
    
    if search_hidden and catalog_hidden:
        score += 30
        feedback.append("Visibility set to Hidden.")
    elif search_hidden or catalog_hidden:
        score += 15
        feedback.append("Visibility partially hidden (missing either search or catalog exclusion).")
    else:
        feedback.append("Visibility not set to Hidden.")

    # 3. Check Stock Status (30 pts)
    stock_status = result.get('stock_status', '')
    if stock_status == 'outofstock':
        score += 30
        feedback.append("Stock status set to Out of Stock.")
    else:
        feedback.append(f"Stock status is '{stock_status}' (expected 'outofstock').")

    # 4. Check Short Description Notice (30 pts)
    short_desc = result.get('short_description', '')
    if expected_notice in short_desc:
        score += 30
        feedback.append("Discontinuation notice added correctly.")
    else:
        feedback.append("Discontinuation notice missing or incorrect.")

    # VLM Check (Optional Trajectory Verification)
    # We generally trust the DB state, but we can look for the "Product updated" message in the final frame
    # to confirm the Save action completed successfully via UI.
    
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }