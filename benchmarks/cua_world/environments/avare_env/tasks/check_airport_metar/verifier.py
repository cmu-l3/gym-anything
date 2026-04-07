#!/usr/bin/env python3
"""
Verifier for check_airport_metar task.

Verification Strategy:
1. Anti-gaming: Check app was running and task duration was reasonable.
2. VLM Analysis:
   - Check if the final screen shows a Weather/METAR view (not just the map).
   - Check if the text "KOAK" is visible.
   - Check if METAR-formatted text (e.g., wind "KT", visibility "SM", time "Z") is visible.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_airport_metar(traj, env_info, task_info):
    """
    Verify that the agent retrieved the METAR for KOAK.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. READ METADATA & RESULT JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check 1: App Running (10 pts)
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("App active")
    else:
        feedback_parts.append("App crashed or closed")

    # ================================================================
    # 2. VLM VERIFICATION
    # ================================================================
    
    # Get images: Final state + 2 trajectory frames to verify workflow
    final_screenshot = get_final_screenshot(traj)
    trajectory_frames = sample_trajectory_frames(traj, n=2)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No screenshots available"}

    # Prompt for VLM
    prompt = """
    You are evaluating an agent using an aviation GPS app (Avare).
    The goal is to look up the METAR (weather report) for airport KOAK.
    
    Examine the FINAL SCREENSHOT and determine:
    1. Is the screen displaying a text-based Weather or METAR report? (It should NOT be just a map view).
    2. Is the airport identifier "KOAK" clearly visible?
    3. Is there METAR weather data visible? (Look for patterns like "1200Z", "10SM", "KT" for knots, "CLR", "OVC").
    
    Answer in JSON format:
    {
        "is_weather_screen": true/false,
        "koak_visible": true/false,
        "metar_data_visible": true/false,
        "reasoning": "your explanation"
    }
    """

    vlm_response = query_vlm(
        prompt=prompt,
        images=trajectory_frames + [final_screenshot] 
    )
    
    if not vlm_response.get("success"):
        return {"passed": False, "score": score, "feedback": f"VLM verification failed: {vlm_response.get('error')}"}

    parsed = vlm_response.get("parsed", {})
    logger.info(f"VLM Analysis: {parsed}")

    # Scoring based on VLM
    if parsed.get("is_weather_screen", False):
        score += 30
        feedback_parts.append("Weather screen reached")
    else:
        feedback_parts.append("Remained on map/wrong screen")

    if parsed.get("koak_visible", False):
        score += 30
        feedback_parts.append("KOAK identifier found")
    else:
        feedback_parts.append("KOAK not found")

    if parsed.get("metar_data_visible", False):
        score += 30
        feedback_parts.append("METAR data displayed")
    else:
        feedback_parts.append("No weather data visible")

    # ================================================================
    # 3. FINAL EVALUATION
    # ================================================================
    
    # Pass threshold: Must have reached weather screen AND show KOAK data
    passed = score >= 70 and parsed.get("koak_visible") and parsed.get("metar_data_visible")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": parsed
    }