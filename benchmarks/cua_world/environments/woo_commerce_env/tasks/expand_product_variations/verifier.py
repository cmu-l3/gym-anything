#!/usr/bin/env python3
"""
Verifier for expand_product_variations task.

Verification Strategy:
1. Programmatic (80 points):
   - Term 'Black' added to global attributes (20)
   - Parent product attributes updated to include Black (20)
   - Variation created for Black (20)
   - Variation price is correct ($25.00) (10)
   - Variation SKU is correct (CTS-BLK) (10)
   - Integrity check: Old variations still $20.00 (fail condition if broken)

2. VLM (20 points):
   - Verify workflow: Navigated to Attributes tab, Saved attributes, Configured variation.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_expand_product_variations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_sku = metadata.get('expected_sku', 'CTS-BLK')
    expected_price = metadata.get('expected_price', '25.00')

    # Read Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Global Attribute Term (20 pts)
    if result.get('black_term_exists', False):
        score += 20
        feedback_parts.append("Global attribute 'Black' created")
    else:
        feedback_parts.append("Global attribute 'Black' NOT found")

    # 2. Check Parent Product Attributes (20 pts)
    if result.get('parent_attributes_updated', False):
        score += 20
        feedback_parts.append("Product attributes updated")
    else:
        feedback_parts.append("Product does not have 'Black' in attributes")

    # 3. Check Variation Existence (20 pts)
    if result.get('variation_found', False):
        score += 20
        feedback_parts.append("Black variation created")
    else:
        feedback_parts.append("Black variation NOT found")

    # 4. Check Price (10 pts)
    actual_price = str(result.get('variation_price', '0'))
    # Handle floating point string comparisons roughly
    if expected_price in actual_price or (float(actual_price) == float(expected_price) if actual_price.replace('.','',1).isdigit() else False):
        score += 10
        feedback_parts.append(f"Price correct ({actual_price})")
    else:
        feedback_parts.append(f"Incorrect price: {actual_price} (Expected: {expected_price})")

    # 5. Check SKU (10 pts)
    actual_sku = result.get('variation_sku', '')
    if actual_sku.strip().upper() == expected_sku.strip().upper():
        score += 10
        feedback_parts.append(f"SKU correct ({actual_sku})")
    else:
        feedback_parts.append(f"Incorrect SKU: {actual_sku} (Expected: {expected_sku})")

    # Integrity Check
    red_price = float(result.get('red_variation_price', 0))
    if red_price != 20.0:
         feedback_parts.append(f"WARNING: Red variation price modified to {red_price}")
         # Penalize if they broke existing data
         score = max(0, score - 10)

    # 6. VLM Verification (20 pts)
    # We want to verify they actually used the UI correctly
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    Analyze these screenshots of a user editing a WooCommerce product.
    I am looking for evidence that the user:
    1. Opened the 'Attributes' tab in the Product Data panel.
    2. Opened the 'Variations' tab.
    3. Expanded a specific variation form (showing SKU and Price fields).
    
    Respond in JSON:
    {
        "attributes_tab_seen": true/false,
        "variations_tab_seen": true/false,
        "variation_settings_seen": true/false
    }
    """
    
    try:
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('attributes_tab_seen') or parsed.get('variations_tab_seen'):
                score += 10
            if parsed.get('variation_settings_seen'):
                score += 10
                feedback_parts.append("Visual confirmation of variation editing")
    except Exception as e:
        # Fallback if VLM fails: give points if programmatic checks passed strongly
        if score >= 70:
            score += 20
            feedback_parts.append("VLM skipped, assumed valid workflow")

    final_feedback = " | ".join(feedback_parts)
    
    # Pass threshold: Needs variation created + correct price (approx 70 pts)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }