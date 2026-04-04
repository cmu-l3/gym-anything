#!/usr/bin/env python3
"""
Verifier for bulk_dispose_assets task.

Verification Logic:
1. Primary: Check /tmp/task_result.json (generated from DB) to verify all 5 assets are "Disposed".
2. Secondary: VLM check on trajectory to confirm bulk action was used (vs 5 individual edits).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bulk_dispose_assets(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_assets = metadata.get('target_assets', ["OLD-PC-01", "OLD-PC-02", "OLD-PC-03", "OLD-PC-04", "OLD-PC-05"])
    
    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------
    # 1. Database Verification
    # ---------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            db_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    asset_states = db_result.get("asset_states", {})
    disposed_count = 0
    
    for asset in target_assets:
        state = asset_states.get(asset, "Unknown")
        if state.lower() == "disposed":
            disposed_count += 1
            score += 12  # 12 points per asset (60 total for DB check)
        else:
            feedback_parts.append(f"{asset}: {state} (Expected: Disposed)")
            
    if disposed_count == len(target_assets):
        feedback_parts.append("All assets correctly marked as Disposed in DB.")
    else:
        feedback_parts.append(f"Only {disposed_count}/{len(target_assets)} assets disposed.")

    # ---------------------------------------------------
    # 2. VLM Verification (Process check)
    # ---------------------------------------------------
    # We want to check if they did a bulk edit or searched correctly
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are verifying an IT Asset Management task. The user should:
    1. Search/Filter for assets named 'OLD-PC'.
    2. Select multiple assets using checkboxes (Bulk Selection).
    3. Use an 'Actions' menu to change status.
    
    Review the screenshots and answer:
    - Did the user perform a search or filter for the assets?
    - Did the user select multiple checkboxes at once?
    - Did the user use a bulk action/edit menu?
    
    Return JSON:
    {
        "searched": boolean,
        "bulk_selected": boolean,
        "bulk_action_menu": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    vlm_data = vlm_result.get('parsed', {})
    
    if vlm_data.get('searched'):
        score += 10
        feedback_parts.append("VLM: Verified search/filter usage.")
    
    if vlm_data.get('bulk_selected'):
        score += 20
        feedback_parts.append("VLM: Verified bulk selection.")
    elif disposed_count == 5:
        # If they did it manually one by one, they still get the outcome, but lose efficiency points
        feedback_parts.append("VLM: No bulk selection detected (efficiency penalty).")
        
    if vlm_data.get('bulk_action_menu'):
        score += 10
        feedback_parts.append("VLM: Verified bulk action menu usage.")

    # ---------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------
    # Max possible: 60 (DB) + 40 (VLM) = 100
    
    passed = (disposed_count == len(target_assets))
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }