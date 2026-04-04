#!/usr/bin/env python3
"""
Verifier for link_asset_to_vendor task.

Verification Strategy:
1. Primary: Database check. We confirmed in setup/export that the link was cleared at start.
   If the link exists in `assets_third_parties` at the end, the agent created it.
2. Anti-gaming: Check if the Asset record's `modified` timestamp > task_start_time.
   (Linking a third party usually updates the parent asset's modified time in Eramba).
3. VLM: Verify UI interaction via trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_asset_to_vendor(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate Database Criteria
    link_exists = result.get("link_exists", False)
    asset_modified_ts = int(result.get("asset_modified_timestamp", 0))
    task_start_ts = int(result.get("task_start_timestamp", 0))

    score = 0
    feedback_parts = []

    # Criterion A: Link exists in DB (40 pts)
    if link_exists:
        score += 40
        feedback_parts.append("Database confirmed: Asset is linked to Vendor.")
    else:
        feedback_parts.append("Database check failed: No link found between 'HR Employee Portal' and 'Workday Inc.'.")

    # Criterion B: Modification Timestamp (20 pts)
    # Check if modification happened after task start
    # Allow 5 seconds tolerance for clock skew
    if asset_modified_ts >= (task_start_ts - 5):
        score += 20
        feedback_parts.append("Asset modification timestamp is valid (occurred during task).")
    elif link_exists:
         # If link exists but timestamp is old, it might be pre-existing (anti-gaming fail)
         # However, we cleared it in setup_task.sh, so this case implies the delete failed 
         # or the timestamp logic is quirky. We penalize but don't fail if link exists.
         feedback_parts.append("Warning: Asset timestamp suggests no modification during task.")
    
    # 4. VLM Verification (40 pts)
    # We look at trajectory frames to see if they visited the Asset Management section
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying an agent's work in Eramba GRC.
    Goal: Link asset 'HR Employee Portal' to vendor 'Workday Inc.'.
    
    Analyze these screenshots (sequence of actions + final state):
    1. Did the agent navigate to an 'Asset Management' or 'Business Assets' list?
    2. Did the agent open an asset named 'HR Employee Portal'?
    3. Is 'Workday Inc.' visible in the Third Parties / Suppliers section in the final state?
    
    Return JSON:
    {
        "navigated_assets": boolean,
        "opened_correct_asset": boolean,
        "vendor_visible_linked": boolean
    }
    """
    
    vlm_score = 0
    try:
        vlm_resp = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        parsed = vlm_resp.get('parsed', {})
        
        if parsed.get('navigated_assets'):
            vlm_score += 10
        if parsed.get('opened_correct_asset'):
            vlm_score += 10
        if parsed.get('vendor_visible_linked'):
            vlm_score += 20
            
        score += vlm_score
        feedback_parts.append(f"Visual verification score: {vlm_score}/40")
        
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if DB passed, give partial credit for VLM
        if link_exists:
            score += 20
            feedback_parts.append("VLM skipped (error), granted partial credit based on DB success.")

    # 5. Final Result
    # Pass threshold: 70 points. 
    # Must have DB link (40) + either timestamp (20) or VLM confirmation (20+) to pass.
    passed = (score >= 70 and link_exists)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }