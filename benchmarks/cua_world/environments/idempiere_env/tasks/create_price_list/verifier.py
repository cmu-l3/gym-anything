#!/usr/bin/env python3
"""
Verifier for create_price_list task.

Checks:
1. Price List created with correct Name, Currency, Flags, Precision.
2. Price List Version created with correct ValidFrom date.
3. Product Prices created correctly for 3 specific products.
4. Anti-gaming: Timestamp checks and record count increase.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_price_list(traj, env_info, task_info):
    """
    Verify the creation of Price List, Version, and Product Prices.
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

    score = 0
    feedback = []
    
    # ----------------------------------------------------------------
    # 1. Price List Verification (30 points)
    # ----------------------------------------------------------------
    pl = result.get('price_list', {})
    if pl.get('exists'):
        score += 15
        feedback.append("Price List created")
        
        # Check attributes
        if pl.get('currency') == 'USD':
            score += 5
        else:
            feedback.append(f"Wrong currency: {pl.get('currency')}")
            
        if pl.get('is_so') == 'Y':
            score += 5
        else:
            feedback.append("Not marked as Sales Price List")
            
        if str(pl.get('precision')) == '2':
            score += 5
        else:
            feedback.append(f"Wrong precision: {pl.get('precision')}")
            
    else:
        feedback.append("Price List '2025 Spring Retail' NOT found")
        # Critical failure
        return {"passed": False, "score": 0, "feedback": "Price List was not created"}

    # ----------------------------------------------------------------
    # 2. Version Verification (10 points)
    # ----------------------------------------------------------------
    ver = result.get('version', {})
    if ver.get('exists'):
        score += 5
        feedback.append("Version created")
        
        if ver.get('valid_from') == '2025-04-01':
            score += 5
        else:
            feedback.append(f"Wrong ValidFrom date: {ver.get('valid_from')}")
    else:
        feedback.append("Price List Version NOT found")

    # ----------------------------------------------------------------
    # 3. Product Price Verification (45 points)
    # ----------------------------------------------------------------
    products = result.get('products', [])
    # Map by name for easy lookup
    prod_map = {p['name']: p for p in products}
    
    targets = [
        {'name': 'Azalea Bush', 'list': 29.99, 'std': 24.99, 'limit': 19.99},
        {'name': 'Elm Tree', 'list': 149.99, 'std': 129.99, 'limit': 109.99},
        {'name': 'Oak Tree', 'list': 249.99, 'std': 219.99, 'limit': 189.99}
    ]
    
    for t in targets:
        name = t['name']
        found = False
        # Fuzzy match key
        for key in prod_map:
            if name in key:
                p_res = prod_map[key]
                found = True
                if not p_res.get('found'):
                    feedback.append(f"Price for {name} missing")
                    continue
                
                # Check prices
                p_score = 0
                match = True
                
                if abs(float(p_res.get('list', 0)) - t['list']) < 0.02:
                    p_score += 5
                else:
                    match = False
                    
                if abs(float(p_res.get('std', 0)) - t['std']) < 0.02:
                    p_score += 5
                else:
                    match = False
                    
                if abs(float(p_res.get('limit', 0)) - t['limit']) < 0.02:
                    p_score += 5
                else:
                    match = False
                
                score += p_score
                if not match:
                    feedback.append(f"Incorrect prices for {name}")
                break
        
        if not found:
            feedback.append(f"Product {name} not found in result")

    # ----------------------------------------------------------------
    # 4. Anti-gaming Verification (15 points)
    # ----------------------------------------------------------------
    # Created timestamp check
    task_start = result.get('task_start', 0)
    pl_created = pl.get('created_ts', 0)
    
    if pl_created >= task_start:
        score += 10
    else:
        feedback.append("Record appears to be pre-existing (timestamp check failed)")
        
    # Count increase check
    initial = result.get('initial_count', 0)
    current = result.get('current_count', 0)
    if current > initial:
        score += 5
    else:
        feedback.append("Price list count did not increase")

    # ----------------------------------------------------------------
    # Final Result
    # ----------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }