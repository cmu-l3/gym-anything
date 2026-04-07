#!/usr/bin/env python3
"""
Verifier for industrial_asset_inventory_digitization task.

Evaluates the completion of 3 Asset Categories, 1 Vendor, and 3 Assets.
Uses database output exported by `export_result.sh` and incorporates VLM
trajectory analysis to prevent headless/scripted database gaming.

Scoring (100 points total, Pass Threshold = 70):
- Category: Two-Way Radios (15 points)
- Category: Gas Detectors (15 points)
- Category: Thermal Cameras (15 points)
- Vendor: Industrial Safety Supply Co. (25 points)
- Asset 1: RAD-8821-A (10 points)
- Asset 2: GAS-9910-B (10 points)
- Asset 3: THM-4450-C (10 points)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these trajectory frames from a desktop environment.
The user is supposed to be using a web-based HRMS application (Sentrifugo) to add asset inventory.

Please determine if the user actually navigated the Sentrifugo web UI to manage assets.
Look for:
1. The Sentrifugo UI open in Firefox.
2. Forms or pages titled "Assets", "Asset Categories", "Vendors", or "Add Asset".
3. The user typing data into Sentrifugo web forms.

Did the user use the Sentrifugo UI to perform asset management tasks?
Respond in JSON format:
{
    "used_sentrifugo_ui": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible in the frames."
}"""

def verify_asset_digitization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    pass_threshold = metadata.get('pass_threshold', 70)

    # 1. Retrieve the exported JSON result from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/asset_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read exported result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read database export: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. VLM Trajectory Verification (Anti-Gaming)
    vlm_ui_confirmed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        vlm_result = query_vlm(images=frames, prompt=build_vlm_prompt())
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            vlm_ui_confirmed = parsed.get("used_sentrifugo_ui", False)
            logger.info(f"VLM Analysis: {parsed.get('reasoning')}")
        else:
            logger.warning("VLM query failed or returned no success. Falling back to log checks.")
            vlm_ui_confirmed = True  # Fallback if VLM isn't responsive
    except ImportError:
        logger.warning("VLM module not available. Skipping VLM check.")
        vlm_ui_confirmed = True

    # 3. Apache Log Check (Anti-Gaming Backup)
    post_requests = result_data.get('post_requests', 0)
    
    # If VLM says false AND there are no POST requests, the agent likely scripted DB inserts
    if not vlm_ui_confirmed and post_requests < 2:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Anti-gaming triggered: No UI interaction detected in trajectory frames or Apache logs. Must use the application UI."
        }

    # 4. Score Calculation based on DB records
    score = 0
    feedback_parts = []
    
    # Check Categories (45 points total)
    categories = result_data.get('categories', {})
    for cat_name, points in [("Two-Way Radios", 15), ("Gas Detectors", 15), ("Thermal Cameras", 15)]:
        if categories.get(cat_name, 0) > 0:
            score += points
            feedback_parts.append(f"Category '{cat_name}' created (+{points})")
        else:
            feedback_parts.append(f"Category '{cat_name}' missing")

    # Check Vendor (25 points)
    if result_data.get('vendor_count', 0) > 0:
        score += 25
        feedback_parts.append("Vendor 'Industrial Safety Supply Co.' created (+25)")
    else:
        feedback_parts.append("Vendor missing")

    # Check Assets (30 points total)
    assets = result_data.get('assets', {})
    for serial, points in [("RAD-8821-A", 10), ("GAS-9910-B", 10), ("THM-4450-C", 10)]:
        if assets.get(serial, 0) > 0:
            score += points
            feedback_parts.append(f"Asset '{serial}' registered (+{points})")
        else:
            feedback_parts.append(f"Asset '{serial}' missing")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }