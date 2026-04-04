#!/usr/bin/env python3
"""
Verifier for Setup Product Line task in Copper POS.

Verification Strategy:
1. VLM (Primary): Analyze trajectory frames to verify:
   - Creation of "Canvas Bags" category
   - Entry of specific items with correct SKUs, Prices, and Stock levels
   - Correct spelling and formatting
2. Programmatic (Secondary):
   - Verify data files were modified (Activity detection)
   - Verify app is running

Refusal to pass if "files_modified" is False (Anti-gaming).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_product_line(traj, env_info, task_info):
    """
    Verify the creation of product variants using VLM and file activity.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_variants = metadata.get('variants', [])
    
    # 1. Retrieve Programmatic Evidence (Activity Check)
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows env, copy_from_env handles the path translation from C:
        # usually /tmp/task_result.json in the "copy" command maps to the container path provided
        # But here we specified C:\Windows\Temp\task_result.json in the PS script.
        # The copy_from_env implementation usually expects a path inside the container.
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result (system error)"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Activity (Anti-Gaming)
    files_modified = result.get('files_modified', False)
    app_running = result.get('app_running', False)
    
    score = 0
    feedback_parts = []
    
    if files_modified:
        score += 10
        feedback_parts.append("Data files updated (Activity detected)")
    else:
        feedback_parts.append("No data written to disk (Did you save?)")
        # If no files changed, they likely didn't save anything. 
        # But we continue to VLM to be sure (maybe they just navigated).

    if app_running:
        score += 5
    
    # 3. VLM Verification (Primary Content Check)
    # We sample frames to catch the data entry process and the final list
    frames = sample_trajectory_frames(traj, n=8)
    final_frame = get_final_screenshot(traj)
    all_images = frames + [final_frame]
    
    # Prompt for VLM
    # We ask to verify the "Canvas Bags" category and the list of items
    prompt = f"""
    You are verifying a data entry task in NCH Copper Point of Sale.
    The agent was supposed to create a category 'Canvas Bags' and add 8 items with specific details.
    
    Review the screenshots (chronological order) and the final state.
    
    1. CATEGORY CHECK: Do you see a category named 'Canvas Bags' created or selected?
    2. ITEM LIST CHECK: Look for the inventory list. Do you see items named 'Premium Canvas Tote...'?
    3. DETAILS CHECK: Can you spot specific values matching these requirements?
       - SKUs starting with 'PCT-' (e.g., PCT-S-NAT, PCT-XL-BLK)
       - Prices like $18.99, $24.99, $32.99, $39.99
       - Stock quantities like 25, 30, 20, 15
    
    Count how many unique 'Premium Canvas Tote' items you can confirm were added/visible in the list.
    
    Output JSON:
    {{
        "category_created": true/false,
        "items_visible_count": <number>,
        "sku_pattern_observed": true/false,
        "prices_correct": true/false,
        "stock_quantities_observed": true/false,
        "feedback": "summary of what you see"
    }}
    """
    
    vlm_result = query_vlm(images=all_images, prompt=prompt)
    
    if not vlm_result or not vlm_result.get("success"):
        return {
            "passed": False, 
            "score": score, 
            "feedback": "VLM verification failed to process images."
        }
        
    parsed = vlm_result.get("parsed", {})
    
    # 4. Scoring Logic
    # Category (20 pts)
    if parsed.get("category_created"):
        score += 20
        feedback_parts.append("Category 'Canvas Bags' created")
    else:
        feedback_parts.append("Category 'Canvas Bags' NOT detected")
        
    # Items (5 pts per item, max 40)
    visible_count = parsed.get("items_visible_count", 0)
    # Cap at 8
    visible_count = min(visible_count, 8)
    score += (visible_count * 5)
    feedback_parts.append(f"{visible_count}/8 items visible")
    
    # Details Accuracy (25 pts total)
    if parsed.get("sku_pattern_observed"):
        score += 10
        feedback_parts.append("SKU pattern correct")
    if parsed.get("prices_correct"):
        score += 10
        feedback_parts.append("Prices appear correct")
    if parsed.get("stock_quantities_observed"):
        score += 5
        feedback_parts.append("Stock quantities observed")
        
    # Final Pass Check
    # Need at least 60 points AND files must be modified AND category must exist
    passed = (score >= 60) and files_modified and parsed.get("category_created")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }