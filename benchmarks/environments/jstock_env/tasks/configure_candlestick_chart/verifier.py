#!/usr/bin/env python3
"""
Verifier for configure_candlestick_chart task.

Combines file-based persistence checks with VLM visual verification.
Since JStock's exact config XML structure can be version-dependent and opaque,
visual verification is the primary signal for "correctness", while file modification
is the primary signal for "effort/persistence".
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_candlestick_chart(traj, env_info, task_info):
    """
    Verify that the agent configured the chart to Candlestick with Volume.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Check File Persistence (20 points)
    # Did the agent trigger a save/config change?
    config_modified = result.get('config_modified', False)
    if config_modified:
        score += 20
        feedback_parts.append("Configuration files were updated")
    else:
        feedback_parts.append("No configuration changes detected (did you close the chart window?)")

    # 3. VLM Visual Verification (80 points)
    # The most reliable way to check chart type is looking at it
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze this screenshot of the JStock software.\n"
        "1. Is a stock price chart window visible?\n"
        "2. Does the chart display 'Candlestick' bars (rectangular bodies with wicks) "
        "or a simple 'Line' graph?\n"
        "3. Is a 'Volume' bar chart/histogram visible at the bottom of the price chart?\n"
        "\n"
        "Answer with JSON: {\"chart_visible\": bool, \"is_candlestick\": bool, \"volume_visible\": bool}"
    )
    
    try:
        vlm_response = query_vlm(
            images=[final_screenshot], 
            prompt=vlm_prompt,
            return_json=True
        )
        
        # Parse VLM response
        chart_visible = vlm_response.get("chart_visible", False)
        is_candlestick = vlm_response.get("is_candlestick", False)
        volume_visible = vlm_response.get("volume_visible", False)
        
        # Scoring logic
        if chart_visible:
            score += 20
            feedback_parts.append("Chart window is visible")
            
            if is_candlestick:
                score += 30
                feedback_parts.append("Chart type is Candlestick")
            else:
                feedback_parts.append("Chart type appears to be Line (expected Candlestick)")
                
            if volume_visible:
                score += 30
                feedback_parts.append("Volume histogram is visible")
            else:
                feedback_parts.append("Volume is NOT visible")
        else:
            feedback_parts.append("No chart window found in final screenshot")
            
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("Visual verification failed due to error")
        # Fallback points if keywords were found in config
        if result.get("found_candlestick_keyword"):
            score += 20
            feedback_parts.append("Fallback: Candlestick keyword found in config")
        if result.get("found_volume_keyword"):
            score += 20
            feedback_parts.append("Fallback: Volume keyword found in config")

    # Final Pass Decision
    # Must have Candlestick visually confirmed OR strong config evidence
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }