#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_map_font_size_large(traj, env_info, task_info):
    """
    Verifies that the user set the map font size to 'Large'.
    
    Criteria:
    1. VLM confirms the final screenshot shows the 'Map font size' setting selected as 'Large'.
    2. (Optional) Internal settings file contains the string 'Large' (passed via JSON).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve Screenshot for VLM
    # The framework handles trajectory screenshots, but we want the high-res final one captured by script
    # explicitly to ensure we see the settings screen.
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
    final_screenshot_path = temp_img.name
    try:
        copy_from_env("/sdcard/task_final.png", final_screenshot_path)
    except Exception as e:
        logger.error(f"Failed to load final screenshot: {e}")
        # Fallback to framework screenshot if specific one fails
        final_screenshot_path = get_final_screenshot(traj)

    if not final_screenshot_path or not os.path.exists(final_screenshot_path):
        return {"passed": False, "score": 0, "feedback": "No evidence screenshot available"}

    # 3. VLM Verification
    # We ask the VLM specifically about the UI state
    prompt = """
    You are verifying an automation task in Sygic GPS Navigation.
    The goal was to set the "Map font size" to "Large".
    
    Analyze the screenshot provided.
    1. Do you see a menu option or setting labeled "Map font size" (or similar)?
    2. Is the value "Large" visible?
    3. Is "Large" selected (e.g., radio button filled, checkmark, or highlighted text)?
    
    Return JSON:
    {
        "setting_visible": true/false,
        "value_large_visible": true/false,
        "is_selected": true/false,
        "reasoning": "..."
    }
    """
    
    vlm_result = query_vlm(prompt=prompt, image=final_screenshot_path)
    
    # Clean up temp image
    if os.path.exists(temp_img.name):
        os.unlink(temp_img.name)

    if not vlm_result.get("success"):
        return {"passed": False, "score": 0, "feedback": f"VLM analysis failed: {vlm_result.get('error')}"}

    parsed = vlm_result.get("parsed", {})
    
    # Scoring
    score = 0
    feedback = []
    
    if parsed.get("setting_visible"):
        score += 30
        feedback.append("Settings menu found.")
    else:
        feedback.append("Could not find 'Map font size' setting in screenshot.")

    if parsed.get("value_large_visible"):
        score += 30
        feedback.append("'Large' option is visible.")

    if parsed.get("is_selected"):
        score += 40
        feedback.append("'Large' is successfully selected.")
    else:
        feedback.append("'Large' does not appear to be the active selection.")

    # Bonus: Check internal file confirmation if available
    if result_data.get("settings_content_match") == "true":
        # This confirms the app actually saved 'Large' to disk
        # We use this to validate the visual score
        feedback.append("(Internal settings file confirmed change)")
    
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }