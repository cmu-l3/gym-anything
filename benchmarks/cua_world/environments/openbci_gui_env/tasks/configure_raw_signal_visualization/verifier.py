#!/usr/bin/env python3
"""
Verifier for configure_raw_signal_visualization task.

Criteria:
1. Agent must load the correct playback file (checked via trajectory/VLM).
2. Agent must disable Notch Filter (checked via VLM on final/trajectory).
3. Agent must disable Bandpass Filter (checked via VLM on final/trajectory).
4. Agent must set vertical scale to 1000 uV (checked via VLM).
5. Agent must save a screenshot of the view (checked via file existence).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_raw_signal_config(traj, env_info, task_info):
    """
    Verifies that the OpenBCI GUI is configured for raw signal visualization.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
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

    # 2. Extract basic metrics
    screenshot_exists = result.get("screenshot_exists", False)
    screenshot_fresh = result.get("screenshot_created_during_task", False)
    app_running = result.get("app_running", False)
    
    # 3. VLM Verification
    # We use the final system screenshot for state verification, 
    # plus the agent's saved screenshot if available.
    
    final_sys_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=4)
    images_to_check = frames + [final_sys_screenshot]
    
    # Construct VLM Prompt
    prompt = """
    You are verifying an OpenBCI GUI task. The user must display RAW EEG data.
    
    Please analyze the images (showing the progression and final state) to answer:
    1. Is the OpenBCI GUI running and showing streaming data (wavy lines moving)?
    2. Look at the "Filters" or "Hardware Settings" panel (usually top left or top bar).
       - Is the 'Notch' filter set to 'None', 'Off', or disabled?
       - Is the 'Bandpass' filter set to 'None', 'Off', or disabled?
    3. Look at the vertical scale on the left side of the Time Series graph.
       - Is the scale set to '1000 uV', '1 mV', or larger? (It should NOT be 'Auto' or small values like '50 uV').
    4. Does the data look 'raw'? (Raw data usually has wandering baselines or DC offsets, whereas filtered data is centered perfectly at 0).
    
    Return JSON:
    {
      "data_streaming": boolean,
      "notch_filter_disabled": boolean,
      "bandpass_filter_disabled": boolean,
      "scale_is_1000uv_or_more": boolean,
      "raw_data_appearance": boolean
    }
    """
    
    vlm_result = query_vlm(
        prompt=prompt,
        images=images_to_check,
        model="gpt-4o" # High capability model required for text reading
    )
    
    vlm_data = vlm_result.get("parsed", {})
    if not vlm_data:
        # Fallback if parsing fails
        logger.warning(f"VLM parsing failed. Raw: {vlm_result.get('response')}")
        vlm_data = {
            "data_streaming": False,
            "notch_filter_disabled": False,
            "bandpass_filter_disabled": False,
            "scale_is_1000uv_or_more": False
        }

    # 4. Scoring
    score = 0
    feedback = []

    # Criterion: App Running (10 pts)
    if app_running:
        score += 10
    else:
        feedback.append("App was not running at the end.")

    # Criterion: Screenshot Evidence (10 pts)
    if screenshot_exists and screenshot_fresh:
        score += 10
        feedback.append("Agent saved the requested screenshot.")
    elif screenshot_exists:
        score += 5
        feedback.append("Agent saved screenshot, but timestamp is suspect.")
    else:
        feedback.append("Agent did not save the result screenshot.")

    # Criterion: Filters Disabled (40 pts)
    if vlm_data.get("notch_filter_disabled"):
        score += 20
        feedback.append("Notch filter disabled.")
    else:
        feedback.append("Notch filter appears active.")

    if vlm_data.get("bandpass_filter_disabled"):
        score += 20
        feedback.append("Bandpass filter disabled.")
    else:
        feedback.append("Bandpass filter appears active.")

    # Criterion: Scale Adjustment (20 pts)
    if vlm_data.get("scale_is_1000uv_or_more"):
        score += 20
        feedback.append("Vertical scale set to raw range (1000uV+).")
    else:
        feedback.append("Vertical scale not clearly set to 1000uV.")

    # Criterion: Streaming/Raw Appearance (20 pts)
    if vlm_data.get("data_streaming"):
        score += 10
        feedback.append("Data is streaming.")
    
    if vlm_data.get("raw_data_appearance"):
        score += 10
        feedback.append("Signal has raw characteristics (DC offset/drift).")

    # Pass logic
    # Must have filters disabled and scale correct to pass meaningful raw signal inspection
    passed = (score >= 70) and vlm_data.get("notch_filter_disabled") and vlm_data.get("bandpass_filter_disabled")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }