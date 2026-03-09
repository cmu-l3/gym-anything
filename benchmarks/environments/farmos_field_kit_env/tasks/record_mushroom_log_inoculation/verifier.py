#!/usr/bin/env python3
"""
Verifier for Mushroom Log Inoculation Task.

Uses VLM (Visual Language Model) to verify the trajectory and final state.
Checks for:
1. Log creation (Activity type)
2. Correct Date (Feb 14, 2025)
3. Specific Notes content (Strain LE-46, Red Oak, etc.)
4. Quantities (50 count, 5.5 lbs)
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any, List

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

# Import VLM utilities provided by the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/Mock for local testing without framework
    logger.warning("gym_anything.vlm not found, using mocks")
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, images): return {"success": False, "error": "VLM not available"}


def verify_mushroom_log(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies the farmOS mushroom log task.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    # Copy result JSON from device
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            device_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read device result: {e}")
        device_result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. VLM Analysis
    # We analyze the final state AND trajectory to confirm data entry details
    # that might be hidden in the list view summary.
    
    frames = sample_trajectory_frames(traj, n=8)  # Sample frames to catch data entry
    final_img = get_final_screenshot(traj)
    
    if not frames and not final_img:
        return {"passed": False, "score": 0, "feedback": "No visual evidence (screenshots) available."}

    images_to_check = frames + ([final_img] if final_img else [])

    # Prompt designed to check specific criteria
    prompt = """
    You are verifying an agent's work in the farmOS Field Kit app.
    The agent was supposed to create an 'Activity' log with specific details.
    
    Review the sequence of images (trajectory) and the final screen.
    
    Check for the following Evidence:
    1. **Log Type**: Did the agent select 'Activity' (not Observation, Harvest, etc.)?
    2. **Date**: Did the agent enter 'Feb 14, 2025' (or 02/14/2025)?
    3. **Notes**: Did the agent type notes containing "Shiitake", "LE-46", "red oak", "crib formation"?
    4. **Quantities**: 
       - Did they enter a quantity of '50' with unit 'count'?
       - Did they enter a quantity of '5.5' with unit 'lbs'?
    5. **Final Save**: Does the final screen show the saved log in the list?
    
    Output JSON:
    {
        "log_type_correct": boolean,
        "date_correct": boolean,
        "notes_content_match": boolean,
        "quantity_50_count_found": boolean,
        "quantity_5_5_lbs_found": boolean,
        "log_saved_and_visible": boolean,
        "confidence": "low|medium|high",
        "reasoning": "string"
    }
    """

    vlm_response = query_vlm(prompt=prompt, images=images_to_check)
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": 0, "feedback": f"VLM Verification failed: {vlm_response.get('error')}"}

    analysis = vlm_response.get("parsed", {})
    logger.info(f"VLM Analysis: {analysis}")

    # 3. Scoring
    score = 0
    feedback_items = []

    # Criteria weights
    if analysis.get("log_type_correct"):
        score += 15
        feedback_items.append("Log type correct (15pts)")
    else:
        feedback_items.append("Log type incorrect or unverified")

    if analysis.get("date_correct"):
        score += 15
        feedback_items.append("Date correct (15pts)")
    else:
        feedback_items.append("Date incorrect/missing")

    if analysis.get("notes_content_match"):
        score += 25
        feedback_items.append("Notes details correct (25pts)")
    else:
        feedback_items.append("Notes missing key details")

    if analysis.get("quantity_50_count_found"):
        score += 15
        feedback_items.append("Quantity 50 count found (15pts)")
    else:
        feedback_items.append("Quantity 50 missing")

    if analysis.get("quantity_5_5_lbs_found"):
        score += 15
        feedback_items.append("Quantity 5.5 lbs found (15pts)")
    else:
        feedback_items.append("Quantity 5.5 lbs missing")

    if analysis.get("log_saved_and_visible"):
        score += 15
        feedback_items.append("Log saved successfully (15pts)")
    else:
        feedback_items.append("Log not seen in final list")

    # Anti-gaming: App must be running
    if device_result.get("app_running", False):
        # Pass, no penalty
        pass
    else:
        score = 0
        feedback_items = ["App was not running at end of task"]

    # Final Pass/Fail
    passed = score >= 60 and analysis.get("log_saved_and_visible")

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_items),
        "details": analysis
    }