#!/usr/bin/env python3
"""
Verifier for Create & Redeem Coupon task in NCH Copper POS.

Verification Strategy:
1. Programmatic: Check if the Coupon Code ("NEW2025") and Item Code ("VASE-001") 
   were written to the application's data files during the task session.
2. Anti-Gaming: Ensure changes happened after task start and app was running.
3. VLM: Verify the visual workflow using trajectory frames.
   - Look for the "Coupon" dialog with correct values.
   - Look for the Sales screen showing the discount applied.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_redeem_coupon(traj, env_info, task_info):
    """
    Verify the agent created the coupon, item, and processed the sale.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_coupon = metadata.get('expected_coupon_code', 'NEW2025')
    expected_item = metadata.get('expected_item_code', 'VASE-001')

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows envs, the path might be re-mapped, but copy_from_env 
        # usually handles the container path mapping. 
        # We try to copy from the location defined in export_result.ps1
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Programmatic Criteria (40 points)
    coupon_found = result.get("coupon_found", False)
    item_found = result.get("item_found", False)
    data_modified = result.get("data_modified", False)
    app_running = result.get("app_running", False)

    if app_running:
        score += 10
    
    if data_modified:
        score += 10
        feedback_parts.append("Application data was modified.")
    
    if coupon_found:
        score += 10
        feedback_parts.append(f"Coupon '{expected_coupon}' found in database.")
    else:
        feedback_parts.append(f"Coupon '{expected_coupon}' NOT found in database.")

    if item_found:
        score += 10
        feedback_parts.append(f"Item '{expected_item}' found in database.")
    else:
        feedback_parts.append(f"Item '{expected_item}' NOT found in database.")

    # 3. Evaluate VLM Criteria (60 points)
    # We sample frames to see the workflow: Item Creation -> Coupon Creation -> Sale
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = f"""
    You are verifying a Point of Sale task. The user was asked to:
    1. Create an item "Ceramic Vase" for $45.00.
    2. Create a coupon "{expected_coupon}" for $10.00 discount.
    3. Process a sale using this coupon.
    
    Review the screenshots and determine:
    A. Did you see a screen or dialog for creating the coupon "{expected_coupon}"?
    B. Did you see a screen or dialog for creating the item "Ceramic Vase"?
    C. Did you see a sales/register screen where the coupon was applied (e.g. "Less Coupon", "-10.00", or "{expected_coupon}" visible on the receipt/list)?
    D. Did the final total reflect the discount (approx $35.00 + tax)?
    
    Respond in JSON:
    {{
        "coupon_creation_seen": true/false,
        "item_creation_seen": true/false,
        "coupon_applied_seen": true/false,
        "discount_verified": true/false,
        "details": "..."
    }}
    """
    
    vlm_result = {}
    if query_vlm:
        try:
            vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
            vlm_result = vlm_response.get("parsed", {})
        except Exception as e:
            logger.error(f"VLM query failed: {e}")

    # Score VLM results
    if vlm_result.get("item_creation_seen"):
        score += 15
        feedback_parts.append("VLM confirmed item creation.")
    
    if vlm_result.get("coupon_creation_seen"):
        score += 15
        feedback_parts.append("VLM confirmed coupon creation.")
        
    if vlm_result.get("coupon_applied_seen"):
        score += 15
        feedback_parts.append("VLM confirmed coupon was applied to sale.")
        
    if vlm_result.get("discount_verified"):
        score += 15
        feedback_parts.append("VLM confirmed correct discounted total.")

    # Final Verification
    passed = score >= 80 and coupon_found and vlm_result.get("coupon_applied_seen")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }