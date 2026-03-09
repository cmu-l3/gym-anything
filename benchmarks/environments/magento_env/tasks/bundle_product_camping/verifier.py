#!/usr/bin/env python3
"""Verifier for Bundle Product Task."""

import json
import logging
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bundle_product(traj, env_info, task_info):
    """
    Verify the created bundle product configuration.
    
    Scoring Criteria (100 pts total):
    - Product exists with correct SKU and Type: 15 pts
    - Product Name matches: 10 pts
    - Product Status is Enabled: 5 pts
    - Exactly 3 Bundle Options exist: 15 pts
    - Option Titles Correct: 10 pts
    - Option Input Types Correct: 10 pts
    - Option Required Flags Correct: 10 pts
    - Selections (SKUs) Correctly Assigned: 10 pts (all or nothing per option logic)
    - Selection Quantity Default Correct: 10 pts
    - Shipment Type is 'Together': 5 pts
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/bundle_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []
    
    # 1. Existence Check (15 pts)
    if not result.get('found'):
        return {"passed": False, "score": 0, "feedback": "Product CAMP-BUNDLE-001 not found."}
        
    if result.get('type_id') == 'bundle':
        score += 15
        feedback.append("Product exists and is 'bundle' type.")
    else:
        feedback.append(f"Product exists but type is '{result.get('type_id')}' (expected 'bundle').")
        
    # 2. Name Check (10 pts)
    expected_name = task_info['metadata']['expected_name']
    if result.get('name', '').lower() == expected_name.lower():
        score += 10
        feedback.append("Product name is correct.")
    else:
        feedback.append(f"Name mismatch: '{result.get('name')}' != '{expected_name}'.")

    # 3. Status Check (5 pts)
    if str(result.get('status')) == '1':
        score += 5
        feedback.append("Product is enabled.")
    else:
        feedback.append("Product is disabled.")

    # 4. Shipment Type Check (5 pts)
    # 0 = Together, 1 = Separately
    if str(result.get('shipment_type')) == '0':
        score += 5
        feedback.append("Shipment Type is 'Together'.")
    else:
        feedback.append(f"Shipment Type incorrect: {result.get('shipment_type')}.")

    # 5. Options Verification
    options = result.get('options', [])
    expected_options = task_info['metadata']['options']
    
    # Option Count (15 pts)
    if len(options) == 3:
        score += 15
        feedback.append("Correct number of option groups (3).")
    else:
        feedback.append(f"Incorrect option count: {len(options)} (expected 3).")

    # Verify each expected option
    titles_score = 0
    types_score = 0
    req_score = 0
    selections_score = 0
    qty_score = 0
    
    # Helper to find matching option by approximate title
    def find_option(exp_title, opts):
        for o in opts:
            if exp_title.lower() in o['title'].lower():
                return o
        return None

    found_opts = 0
    for exp_opt in expected_options:
        matched = find_option(exp_opt['title'], options)
        if matched:
            found_opts += 1
            # Title match (already checked loosely by find) -> Accumulate score
            # We give full points if all 3 match, partial otherwise
            
            # Type Check
            # Magento DB types: radio, select, checkbox, multi
            # Task types: radio, select, checkbox
            if matched['type'] == exp_opt['type']:
                types_score += 1
            else:
                feedback.append(f"Option '{exp_opt['title']}' type mismatch: {matched['type']} != {exp_opt['type']}")

            # Required Check
            if bool(matched['required']) == exp_opt['required']:
                req_score += 1
            else:
                feedback.append(f"Option '{exp_opt['title']}' required flag mismatch.")

            # Selections Check
            matched_skus = [s['sku'] for s in matched['selections']]
            expected_skus = exp_opt['skus']
            
            # Check if all expected SKUs are present
            if set(expected_skus).issubset(set(matched_skus)):
                selections_score += 1
            else:
                feedback.append(f"Option '{exp_opt['title']}' missing products. Found: {matched_skus}")
                
            # Quantity Check (default 1)
            # Just check if any selection has qty 1
            if all(s['qty'] >= 1.0 for s in matched['selections']):
                qty_score += 1

    # Apply Option Scores normalized to totals
    # Titles: 10 pts total
    if found_opts >= 3: score += 10
    elif found_opts > 0: score += 3 * found_opts
    
    # Types: 10 pts total (approx 3.3 each)
    if types_score >= 3: score += 10
    else: score += int(types_score * 3.3)
    
    # Required: 10 pts total
    if req_score >= 3: score += 10
    else: score += int(req_score * 3.3)
    
    # Selections: 10 pts total
    if selections_score >= 3: score += 10
    else: score += int(selections_score * 3.3)
    
    # Qty: 10 pts total
    if qty_score >= 3: score += 10
    else: score += int(qty_score * 3.3)

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }