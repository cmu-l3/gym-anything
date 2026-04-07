#!/usr/bin/env python3
"""
Verifier for configure_bipolar_srb2_montage task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_bipolar_srb2_montage(traj: Any, env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the OpenBCI GUI SRB2 settings were configured correctly.
    
    Criteria:
    1. Agent saved a screenshot (proof of intent).
    2. VLM confirms Hardware Settings panel is OPEN.
    3. VLM confirms SRB2 column toggles match pattern:
       Ch 1,3,5,7: OFF
       Ch 2,4,6,8: ON
    """
    
    # 1. Setup and Load JSON Result
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Extract Basic File Signals (20 points max)
    score = 0
    feedback = []
    
    if result.get("app_running", False):
        score += 5
    else:
        feedback.append("OpenBCI GUI was closed (should remain open)")
        
    if result.get("agent_screenshot_exists", False):
        if result.get("agent_screenshot_valid_time", False):
            if result.get("agent_screenshot_size", 0) > 10000:
                score += 15
                feedback.append("Valid agent screenshot found")
            else:
                score += 5
                feedback.append("Agent screenshot exists but is suspiciously small")
        else:
            feedback.append("Agent screenshot has invalid timestamp (pre-dates task)")
    else:
        feedback.append("Agent did not save the requested screenshot")
        
    # 3. VLM Verification (80 points max)
    # We use the final state screenshot captured by export_result.sh
    # We could also use the agent's screenshot if it exists, but system screenshot is harder to fake.
    
    # Determine which image to use for VLM
    image_to_verify = None
    
    # Try to get the final system screenshot
    try:
        # We need to get the image data from the container or trajectory
        # Since 'traj' usually contains frames, we can use the last frame
        if traj and len(traj) > 0:
            # Heuristic: Use the last frame from trajectory
             from gym_anything.vlm import get_final_screenshot
             image_to_verify = get_final_screenshot(traj)
    except Exception as e:
        logger.warning(f"Could not extract frame from trajectory: {e}")
        
    if not image_to_verify:
        feedback.append("No visual evidence available for VLM verification")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

    if not query_vlm:
        return {"passed": False, "score": score, "feedback": "VLM not available for verification"}

    # VLM Prompt
    prompt = """
    You are verifying an OpenBCI GUI configuration task.
    Look at the 'Hardware Settings' panel in the interface (usually a grid of buttons).
    
    Focus specifically on the 'SRB2' column.
    
    I need to verify the state of the SRB2 toggle buttons for Channels 1 through 8.
    - 'ON' usually looks like a filled/colored button.
    - 'OFF' usually looks like an empty/greyed-out button.
    
    Required State:
    - Channel 1: OFF
    - Channel 2: ON
    - Channel 3: OFF
    - Channel 4: ON
    - Channel 5: OFF
    - Channel 6: ON
    - Channel 7: OFF
    - Channel 8: ON
    
    Questions:
    1. Is the Hardware Settings panel open/visible?
    2. Do the SRB2 settings match the alternating OFF/ON pattern described above?
    
    Return JSON:
    {
        "hardware_panel_visible": boolean,
        "srb2_pattern_correct": boolean,
        "channel_errors": [list of channel numbers with wrong state, or empty],
        "confidence": "low|medium|high"
    }
    """
    
    vlm_response = query_vlm(image=image_to_verify, prompt=prompt)
    
    if not vlm_response.get("success"):
        feedback.append("VLM analysis failed")
    else:
        analysis = vlm_response.get("parsed", {})
        
        # Hardware Panel Open (15 pts)
        if analysis.get("hardware_panel_visible", False):
            score += 15
            feedback.append("Hardware settings panel is visible")
        else:
            feedback.append("Hardware settings panel not found")
            
        # Pattern Correctness (65 pts)
        if analysis.get("srb2_pattern_correct", False):
            score += 65
            feedback.append("SRB2 alternating configuration verified")
        else:
            # Partial credit logic
            errors = analysis.get("channel_errors", [])
            if isinstance(errors, list):
                correct_count = 8 - len(errors)
                # 8 points per correct channel approx
                partial_points = correct_count * 8
                score += partial_points
                feedback.append(f"SRB2 configuration partially correct ({correct_count}/8 channels)")
            else:
                feedback.append("SRB2 configuration incorrect")

    passed = score >= 60 and analysis.get("hardware_panel_visible", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }