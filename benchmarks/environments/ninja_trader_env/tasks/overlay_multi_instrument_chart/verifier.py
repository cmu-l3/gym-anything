#!/usr/bin/env python3
"""
Verifier for overlay_multi_instrument_chart task in NinjaTrader.

Verifies:
1. Workspace file was modified after task start.
2. A single chart window contains both SPY and AAPL (overlay).
3. SMA indicators are applied to the series.
4. VLM visual verification of the chart overlay.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_overlay_multi_instrument_chart(traj, env_info, task_info):
    """
    Verify the overlay chart task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Get Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        # Note: The export script saves to Desktop/task_result.json in the Windows VM
        # copy_from_env needs the path inside the container.
        # Assuming the env mapping is correct for C:\Users\Docker\Desktop -> /home/ga/Desktop or similar,
        # OR if copy_from_env handles Windows paths directly.
        # Based on env spec, it's Windows. We'll try the absolute Windows path.
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        # If file missing, return specific feedback
        return {"passed": False, "score": 0, "feedback": "Result file not found (Agent may not have saved workspace)"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Programmatic Criteria
    score = 0
    feedback = []
    
    # Criterion 1: Workspace Modified (15 pts)
    if result_data.get("workspace_modified", False):
        score += 15
        feedback.append("Workspace saved successfully.")
    else:
        feedback.append("Workspace not saved.")

    # Criterion 2: Same Chart Overlay (30 pts)
    if result_data.get("same_chart_overlay", False):
        score += 30
        feedback.append("Correctly overlaid SPY and AAPL on the same chart.")
    else:
        if result_data.get("spy_present") and result_data.get("aapl_present"):
            feedback.append("Found SPY and AAPL, but they appear to be in separate charts (not overlaid).")
        else:
            feedback.append("Did not find both SPY and AAPL in the workspace.")

    # Criterion 3: Indicators (20-35 pts)
    sma_count = result_data.get("sma_count", 0)
    if sma_count >= 2:
        score += 35 # 20 for presence + 15 for count
        feedback.append(f"Found {sma_count} SMA indicators.")
    elif sma_count == 1:
        score += 20
        feedback.append("Found only 1 SMA indicator (expected 2).")
    else:
        feedback.append("No SMA indicators found on the overlaid chart.")

    # Criterion 4: Timeframe (10 pts)
    if result_data.get("timeframe_correct", False):
        score += 10
        feedback.append("Daily timeframe correct.")

    # 3. VLM Verification (10 pts)
    # Check visual trajectory
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a NinjaTrader task. The goal is to have ONE chart window containing TWO overlaid price lines (SPY and AAPL).
    
    Look at the final screenshot and the trajectory:
    1. Do you see a SINGLE chart window (not two separate windows side-by-side)?
    2. Does that chart show TWO distinct price series (e.g., candlesticks and a line, or two lines) interacting?
    3. Do you see moving average lines (smooth curves) overlaid on the prices?
    
    Reply in JSON:
    {
        "single_window": true/false,
        "multiple_series_visible": true/false,
        "indicators_visible": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("single_window") and parsed.get("multiple_series_visible"):
            vlm_score = 10
            feedback.append("Visual verification passed: Overlaid chart visible.")
        else:
            feedback.append(f"Visual verification failed: {parsed}")
    
    score += vlm_score

    # Final Pass Logic
    # Must have the overlay programmatically confirmed OR visually confirmed + workspace modified
    passed = (score >= 70) and (result_data.get("same_chart_overlay", False))

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }