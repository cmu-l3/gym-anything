#!/usr/bin/env python3
"""
Verifier for analyze_alpha_playback_fft task.

Verification Strategy:
1. File Check: Confirm agent saved the screenshot as requested (20 pts).
2. VLM Verification: Analyze the screen state (using either agent's screenshot or final system screenshot) for:
   - Playback Mode active (progress bar, file name) (30 pts).
   - FFT Plot Widget visible with Max Freq set to ~40Hz (40 pts).
   - Data streaming (waveforms visible) (10 pts).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_alpha_playback_fft(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Screenshot File Existence (20 pts)
    # ---------------------------------------------------------
    agent_screenshot_path = result.get('agent_screenshot_path', '')
    if result.get('agent_screenshot_exists', False):
        if result.get('agent_screenshot_created_during_task', False):
            if result.get('agent_screenshot_size', 0) > 10000: # >10KB
                score += 20
                feedback_parts.append("✅ Screenshot file created successfully.")
            else:
                score += 5
                feedback_parts.append("⚠️ Screenshot file exists but is suspiciously small.")
        else:
            feedback_parts.append("❌ Screenshot file existed before task start (anti-gaming).")
    else:
        feedback_parts.append("❌ Agent failed to save the screenshot to the specified path.")

    # ---------------------------------------------------------
    # Prepare Image for VLM Verification
    # ---------------------------------------------------------
    # Prefer the agent's screenshot if valid, otherwise use the system final screenshot
    image_to_verify = None
    
    # Try to retrieve agent's screenshot
    if result.get('agent_screenshot_exists', False):
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env(agent_screenshot_path, temp_img.name)
            image_to_verify = temp_img.name
            feedback_parts.append("ℹ️ Analyzing agent's screenshot.")
        except Exception:
            logger.warning("Could not copy agent screenshot, falling back to system screenshot.")

    # Fallback to system screenshot (or trajectory final)
    if not image_to_verify:
        image_to_verify = get_final_screenshot(traj)
        feedback_parts.append("ℹ️ Analyzing final screen state (agent screenshot missing/inaccessible).")

    if not image_to_verify:
         return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | ❌ No visual evidence available."
        }

    # ---------------------------------------------------------
    # Criterion 2, 3, 4: VLM Visual Analysis (80 pts)
    # ---------------------------------------------------------
    prompt = """
    Analyze this OpenBCI GUI screenshot.
    
    1. **Playback Mode**: Is the GUI in Playback mode? Look for a playback progress bar/scrubber at the top or 'Playback' text in the data source area.
    2. **FFT Configuration**: Is the 'FFT Plot' widget visible? Look for a graph with Frequency (Hz) on the X-axis.
    3. **Max Frequency**: Does the FFT graph X-axis end around 40 Hz (or 30-50Hz)? Or is there a button labeled "40 Hz" or "Max Freq 40"? (Standard is usually 60Hz or 120Hz).
    4. **Data Streaming**: Are there visible waveforms in the Time Series or data in the FFT? (Not a blank/flat screen).
    
    Return JSON:
    {
      "is_playback_mode": true/false,
      "fft_widget_visible": true/false,
      "max_frequency_approx_40hz": true/false,
      "data_is_streaming": true/false
    }
    """
    
    try:
        vlm_response = query_vlm(
            prompt=prompt,
            images=[image_to_verify]
        )
        analysis = vlm_response.get('parsed', {})
        
        # Check Playback Mode (30 pts)
        if analysis.get('is_playback_mode', False):
            score += 30
            feedback_parts.append("✅ Playback mode active.")
        else:
            feedback_parts.append("❌ Playback mode not detected.")

        # Check FFT Config (40 pts total)
        if analysis.get('fft_widget_visible', False):
            if analysis.get('max_frequency_approx_40hz', False):
                score += 40
                feedback_parts.append("✅ FFT visible and Max Freq set to ~40Hz.")
            else:
                score += 20
                feedback_parts.append("⚠️ FFT visible but Max Freq does not appear to be 40Hz.")
        else:
            feedback_parts.append("❌ FFT Plot widget not found.")

        # Check Data Streaming (10 pts)
        if analysis.get('data_is_streaming', False):
            score += 10
            feedback_parts.append("✅ Data appears to be streaming.")
        else:
            feedback_parts.append("❌ Waveforms/data not visible (stream might be stopped).")
            
    except Exception as e:
        feedback_parts.append(f"⚠️ VLM analysis failed: {e}")
        # Grace points if file existed
        if score == 20: score += 10 

    # Clean up temp image
    if image_to_verify and os.path.exists(image_to_verify) and 'tmp' in image_to_verify:
        try:
            os.unlink(image_to_verify)
        except:
            pass

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }