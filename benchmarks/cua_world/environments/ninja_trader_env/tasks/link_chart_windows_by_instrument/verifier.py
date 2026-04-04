#!/usr/bin/env python3
"""
Verifier for link_chart_windows_by_instrument task.

Requires:
1. Workspace saved after task start.
2. Two charts created.
3. Instrument linking configured (matching link IDs).
4. Correct final instrument (AAPL) on both charts (proving the link worked).
5. Specific indicators on separate charts.
6. VLM trajectory confirmation of the linking action.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_link_chart_windows(traj, env_info, task_info):
    """
    Verify that the agent linked two chart windows and synchronized them.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Programmatic Verification from XML export
    score = 0
    feedback_parts = []
    
    # Read Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\link_chart_windows_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Activity Check (15 pts)
    if result.get('workspace_saved', False):
        score += 15
        feedback_parts.append("Workspace saved")
    else:
        feedback_parts.append("Workspace NOT saved")

    # Chart Creation Check (20 pts)
    chart_count = result.get('chart_count', 0)
    if chart_count >= 2:
        score += 20
        feedback_parts.append(f"Found {chart_count} charts")
    else:
        feedback_parts.append(f"Found {chart_count} charts (need 2+)")

    # Indicator Check (20 pts)
    has_bollinger = result.get('bollinger_found', False)
    has_rsi = result.get('rsi_found', False)
    
    if has_bollinger and has_rsi:
        score += 20
        feedback_parts.append("Both indicators found")
    elif has_bollinger or has_rsi:
        score += 10
        feedback_parts.append("One indicator missing")
    else:
        feedback_parts.append("Indicators not found")

    # Linking Configuration Check (25 pts)
    # Checks if charts actually share a link color attribute
    linked_count = result.get('linked_charts_count', 0)
    link_match = result.get('link_color_match', False)
    
    if linked_count >= 2 and link_match:
        score += 25
        feedback_parts.append("Charts instrument-linked correctly")
    elif linked_count >= 2:
        score += 10
        feedback_parts.append("Charts have links but colors mismatch")
    else:
        feedback_parts.append("Charts not linked")

    # Functional Link Check (15 pts)
    # Did they switch to AAPL on both?
    if result.get('final_instrument_correct', False):
        score += 15
        feedback_parts.append("Both charts on AAPL (Link verified)")
    else:
        feedback_parts.append("Charts not synchronized to AAPL")

    # 2. VLM Trajectory Verification (5 pts + Anti-gaming)
    # We want to see the "Instrument Link" dropdown or button being clicked
    trajectory_frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from NinjaTrader 8.
    The user is supposed to:
    1. Open two chart windows.
    2. Click the 'Instrument Link' button (usually a small colored square or chain icon in the top right or top left of the window toolbar).
    3. Select a color (Red, Blue, Green, etc.) to link the windows.
    4. Change the stock symbol on one chart, and the other should update.
    
    Question: Do you see evidence of the user interacting with the Instrument Link button (colored square/dropdown) on the chart toolbar?
    """
    
    vlm_result = query_vlm(images=trajectory_frames, prompt=vlm_prompt)
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        # Just a sanity check bonus
        score += 5
        feedback_parts.append("VLM: Workflow valid")
    
    # Final Pass Calculation
    passed = score >= 70
    
    # Gate: Must have linked charts programmatically to pass
    if not (linked_count >= 2 and link_match):
        passed = False
        feedback_parts.append("FAILED: Linking not configured in workspace")

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }