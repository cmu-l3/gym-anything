#!/usr/bin/env python3
"""
Verifier for Bulk Update Product Category Pricing task.

Logic:
1. Load initial and final price states from result JSON.
2. Calculate expected prices for Target group (Clothing): Initial * 1.15.
3. Verify Control group (Electronics) prices did NOT change.
4. Use VLM to verify the "Bulk Actions" interface was used (process verification).
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_update_category_pricing(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

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

    initial = result.get("initial_state", {})
    final = result.get("final_state", {})
    
    score = 0
    feedback = []
    
    # 2. Verify Target Group (Clothing) - 50 Points
    # Logic: New Price must be Initial Price * 1.15 (within small float tolerance)
    clothing_initial = initial.get("clothing", {})
    clothing_final = final.get("clothing", {})
    
    target_passed = True
    target_checked = 0
    
    for product, start_price in clothing_initial.items():
        end_price = clothing_final.get(product)
        
        if start_price is None or end_price is None:
            target_passed = False
            feedback.append(f"Missing data for {product}")
            continue
            
        # Expected: Round to 2 decimals
        expected = round(start_price * 1.15, 2)
        
        # Check tolerance (0.01)
        if abs(end_price - expected) <= 0.01:
            target_checked += 1
        else:
            target_passed = False
            feedback.append(f"{product}: Expected {expected}, got {end_price}")

    if target_passed and target_checked > 0:
        score += 50
        feedback.append("All target clothing items updated correctly (+15%).")
    else:
        feedback.append("Target pricing update failed.")

    # 3. Verify Control Group (Electronics) - 30 Points
    # Logic: Prices must be exactly equal to initial
    electronics_initial = initial.get("electronics", {})
    electronics_final = final.get("electronics", {})
    
    control_passed = True
    for product, start_price in electronics_initial.items():
        end_price = electronics_final.get(product)
        if abs(start_price - end_price) > 0.01:
            control_passed = False
            feedback.append(f"SAFETY FAIL: {product} changed from {start_price} to {end_price}")

    if control_passed:
        score += 30
        feedback.append("Control group (Electronics) untouched.")
    else:
        feedback.append("Collateral damage detected in Electronics category.")

    # 4. VLM Process Verification - 20 Points
    # Did the agent use the bulk editor?
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are verifying a WooCommerce task where the user must bulk edit product prices.
    Look at these screenshots of the user's workflow.
    
    I am looking for evidence of the "Bulk Edit" feature being used.
    
    Signs of success:
    1. A list of products with checkboxes selected (specifically filtered for Clothing).
    2. The "Bulk actions" dropdown menu being used (selecting "Edit").
    3. The "Bulk Edit" panel appearing (an inline form appearing inside the table header/top area).
    4. The "Price" field in the bulk edit panel being set to "Increase existing price by (fixed amount or %)".
    
    Return JSON:
    {
        "bulk_edit_panel_seen": boolean,
        "category_filter_used": boolean,
        "confidence": "high/medium/low"
    }
    """
    
    vlm_score = 0
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("bulk_edit_panel_seen"):
                vlm_score += 20
                feedback.append("VLM confirmed usage of Bulk Edit panel.")
            elif parsed.get("category_filter_used"):
                vlm_score += 10
                feedback.append("VLM confirmed category filtering, but missed bulk panel details.")
            else:
                feedback.append("VLM could not confirm bulk edit workflow.")
        else:
            feedback.append("VLM query failed.")
    except Exception as e:
        logger.warning(f"VLM check error: {e}")
        # Fallback: if data is correct, give partial credit for workflow
        if target_passed and control_passed:
            vlm_score += 10
            feedback.append("VLM failed, granting partial workflow points based on result.")

    score += vlm_score

    # Final Result
    passed = (score >= 90) # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }