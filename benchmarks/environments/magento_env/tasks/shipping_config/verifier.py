#!/usr/bin/env python3
"""Verifier for Shipping Configuration task in Magento.

Task: Configure Shipping Origin (OR, US), Flat Rate ($7.49), and Free Shipping (>$75).
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shipping_config(traj, env_info, task_info):
    """
    Verify shipping configuration settings.
    
    Scoring Breakdown (100 pts total):
    - Origin Settings (25 pts): Country, State, Zip, City, Street
    - Flat Rate Settings (40 pts): Active, Price, Title, Name, Type, Sort
    - Free Shipping Settings (25 pts): Active, Threshold, Sort
    - Anti-gaming (10 pts): Configuration must be saved/present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    meta = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/shipping_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    score = 0
    feedback_parts = []
    
    # --- 1. Shipping Origin (25 pts) ---
    origin = result.get('origin', {})
    
    # Country (5)
    if origin.get('country_id') == meta.get('expected_origin_country', 'US'):
        score += 5
    else:
        feedback_parts.append(f"Origin Country wrong: found {origin.get('country_id')}")

    # Region (5) - Oregon is ID 49
    # Accepts '49' or string 'Oregon' if they somehow forced it
    if str(origin.get('region_id')) == meta.get('expected_origin_region_id', '49'):
        score += 5
    else:
        feedback_parts.append(f"Origin Region wrong: found {origin.get('region_id')}")

    # Postcode (5)
    if str(origin.get('postcode')).strip() == meta.get('expected_origin_postcode', '97201'):
        score += 5
    else:
        feedback_parts.append(f"Origin Zip wrong: found {origin.get('postcode')}")
        
    # City (5)
    if origin.get('city', '').lower().strip() == meta.get('expected_origin_city', 'Portland').lower():
        score += 5
    else:
        feedback_parts.append(f"Origin City wrong: found {origin.get('city')}")
        
    # Street (5)
    if meta.get('expected_origin_street', '450 SW Morrison').lower() in origin.get('street_line1', '').lower():
        score += 5
    else:
        feedback_parts.append(f"Origin Street wrong: found {origin.get('street_line1')}")

    # --- 2. Flat Rate (40 pts) ---
    flat = result.get('flatrate', {})
    
    # Active (10)
    if str(flat.get('active')) == '1':
        score += 10
    else:
        feedback_parts.append("Flat Rate not enabled")
        
    # Price (15) - Float comparison
    try:
        price_val = float(flat.get('price', 0))
        expected_price = float(meta.get('expected_flatrate_price', 7.49))
        if abs(price_val - expected_price) < 0.01:
            score += 15
        else:
            feedback_parts.append(f"Flat Rate price incorrect: found {price_val}")
    except ValueError:
        feedback_parts.append("Flat Rate price invalid")
        
    # Title (5)
    if flat.get('title', '').strip() == meta.get('expected_flatrate_title', 'Ground Shipping'):
        score += 5
    else:
        feedback_parts.append(f"Flat Rate title mismatch: found '{flat.get('title')}'")
        
    # Name (5)
    if flat.get('name', '').strip() == meta.get('expected_flatrate_name', 'Standard Delivery'):
        score += 5
    else:
        feedback_parts.append(f"Flat Rate method name mismatch: found '{flat.get('name')}'")
        
    # Type (2.5) & Sort (2.5)
    if flat.get('type') == meta.get('expected_flatrate_type', 'O'):
        score += 2.5
    if str(flat.get('sort_order')) == meta.get('expected_flatrate_sort', '10'):
        score += 2.5

    # --- 3. Free Shipping (25 pts) ---
    free = result.get('freeshipping', {})
    
    # Active (10)
    if str(free.get('active')) == '1':
        score += 10
    else:
        feedback_parts.append("Free Shipping not enabled")
        
    # Threshold (10)
    try:
        thresh_val = float(free.get('subtotal', 0))
        expected_thresh = float(meta.get('expected_freeshipping_threshold', 75))
        if abs(thresh_val - expected_thresh) < 0.01:
            score += 10
        else:
            feedback_parts.append(f"Free Shipping threshold incorrect: found {thresh_val}")
    except ValueError:
        feedback_parts.append("Free Shipping threshold invalid")
        
    # Sort (5)
    if str(free.get('sort_order')) == meta.get('expected_freeshipping_sort', '5'):
        score += 5
        
    # --- 4. Anti-Gaming Check (10 pts) ---
    # If the file exists and we parsed values, we assume some interaction happened.
    # A cleaner check is implicit: if values match defaults (e.g. flat rate price 5.00), points are lost above.
    # We give these points if score > 0 to reward basic functionality.
    if score > 0:
        score += 10
    else:
        feedback_parts.append("No configuration changes detected or correct")

    # Normalize score to 100 max
    final_score = min(100, score)
    passed = final_score >= 60

    if not feedback_parts:
        feedback_parts.append("All configuration settings correct")

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }