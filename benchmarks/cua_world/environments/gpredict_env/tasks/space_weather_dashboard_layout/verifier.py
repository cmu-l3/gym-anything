#!/usr/bin/env python3
"""
Verifier for space_weather_dashboard_layout task.

Verifies:
1. Space_Weather module was created during the task.
2. Required weather satellites were added.
3. Module layout was changed to a multi-pane layout (expected: All views narrow, index 7).
4. Ground track length was changed to 3.
5. VLM verification ensures the UI actually reflects a multi-pane layout.
"""

import json
import os
import re
import tempfile
import logging

# Use the framework's VLM utility for visual confirmation
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
Analyze this screenshot of the GPredict application.
Look closely at the active tracking module window. 
Does the active module display a multi-pane layout (i.e., multiple different views at the same time, such as a Map view, a circular Polar/radar view, and a List view visible simultaneously on the screen)?

Respond with a JSON object exactly like this:
{
    "has_multiple_panes": true/false,
    "reasoning": "Brief explanation of what views you see"
}
"""

def verify_space_weather_dashboard_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_sats = metadata.get('required_satellites', [37849, 33591, 43689, 41866])
    expected_layout = metadata.get('expected_layout_index', 7)
    expected_track = metadata.get('expected_track_length', 3)

    # 1. Retrieve JSON result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/space_weather_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    module_exists = result.get('module_exists', False)
    created_during_task = result.get('module_created_during_task', False)
    content_str = result.get('module_content', '')

    # CRITERION 1: Module Creation (20 points)
    if not module_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Space_Weather module was not found."
        }
    
    if created_during_task:
        score += 20
        feedback_parts.append("Module successfully created")
    else:
        feedback_parts.append("Warning: Module exists but appears created before task start")

    # Parse module config (format uses pipes '|' instead of newlines from export script)
    satellites_match = re.search(r'SATELLITES=([^\|]+)', content_str, re.IGNORECASE)
    layout_match = re.search(r'LAYOUT=(\d+)', content_str, re.IGNORECASE)
    track_match = re.search(r'TRACK=(\d+)', content_str, re.IGNORECASE)

    # CRITERION 2: Satellites (30 points)
    if satellites_match:
        sat_str = satellites_match.group(1)
        found_sats = 0
        for sat in required_sats:
            if str(sat) in sat_str:
                found_sats += 1
        
        sat_score = int((found_sats / len(required_sats)) * 30)
        score += sat_score
        feedback_parts.append(f"Satellites: {found_sats}/{len(required_sats)} added")
    else:
        feedback_parts.append("Satellites configuration missing from module")

    # CRITERION 3: Layout Property Check (15 points programmatic + 10 points VLM)
    layout_val = int(layout_match.group(1)) if layout_match else 0
    if layout_val == expected_layout:
        score += 15
        feedback_parts.append("Layout set to 'All views narrow' (7)")
    elif layout_val == 6:  # All views (standard)
        score += 10
        feedback_parts.append("Layout set to 'All views' (6) instead of narrow")
    elif layout_val > 2:  # Any multi-pane layout
        score += 5
        feedback_parts.append(f"Layout changed to multi-pane ID {layout_val}")
    else:
        feedback_parts.append(f"Layout unchanged or single view (ID {layout_val})")

    # CRITERION 4: Ground Track Property (15 points)
    track_val = int(track_match.group(1)) if track_match else 1
    if track_val == expected_track:
        score += 15
        feedback_parts.append(f"Ground track set to {expected_track} orbits")
    else:
        feedback_parts.append(f"Ground track length incorrect (found {track_val})")

    # CRITERION 5: VLM Visual Verification of Multiple Panes (10 points)
    vlm_score = 0
    try:
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_response = query_vlm(images=[final_img], prompt=VLM_PROMPT)
            parsed = vlm_response.get("parsed", {})
            if parsed.get("has_multiple_panes") is True:
                vlm_score = 10
                feedback_parts.append("VLM confirms multi-pane layout visible")
            else:
                feedback_parts.append("VLM did not detect multi-pane layout on screen")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification skipped/failed")
    
    score += vlm_score

    # Final logic
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }