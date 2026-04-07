#!/usr/bin/env python3
"""
Verifier for isolate_motor_channels_screenshot task.

Criteria:
1. App-Generated Screenshot (30 pts): Agent used the GUI's camera button.
2. VLM Verification (70 pts):
   - Playback mode active (10 pts)
   - Correct channel isolation (Channels 3,4 visible; 1,2,5,6,7,8 off) (50 pts)
   - Data is streaming/visible (10 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_isolate_motor_channels_screenshot(traj, env_info, task_info):
    # 1. Setup and Copy Results
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "System error: Missing verification tools"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Verify App-Generated Screenshot (30 pts)
    if result_data.get("app_screenshot_created", False):
        score += 30
        feedback_parts.append("✅ App-generated screenshot found")
        # Optional: We could VLM the app screenshot specifically, but the system screenshot 
        # covers the state well enough for the logic check.
    else:
        feedback_parts.append("❌ No app-generated screenshot found (did you click the camera icon?)")

    # 3. VLM Verification of State (70 pts)
    # We look at the final screenshot to confirm channel state
    
    final_screenshot = get_final_screenshot(traj)
    
    prompt = """
    You are verifying an OpenBCI GUI task. 
    The goal is to isolate Channel 3 and Channel 4.
    
    Look at the 'Time Series' widget (usually the large graph with scrolling waveforms).
    
    1. Are there exactly 2 active scrolling waveforms visible? 
    2. Check the channel number buttons (1-8) usually on the left of the Time Series.
       - Are buttons 1, 2, 5, 6, 7, 8 turned OFF (greyed out/dimmed)?
       - Are buttons 3 and 4 turned ON (colored/highlighted)?
    3. Is the data streaming (do the lines look like EEG waves, not flat lines)?
    4. Is the interface in PLAYBACK mode (look for a playback bar/file name at the top)?
    
    Answer in JSON:
    {
      "playback_mode": boolean,
      "only_two_channels_visible": boolean,
      "channels_3_and_4_active": boolean,
      "others_inactive": boolean,
      "data_streaming": boolean
    }
    """
    
    vlm_response = query_vlm(
        prompt=prompt,
        images=[final_screenshot]
    )
    
    try:
        analysis = vlm_response.get('parsed', {})
        
        # Check Playback Mode (10 pts)
        if analysis.get('playback_mode', False):
            score += 10
            feedback_parts.append("✅ Playback mode active")
        else:
            feedback_parts.append("⚠️ Playback mode not detected")
            
        # Check Channel Isolation (50 pts)
        # We need strict confirmation that ONLY specific channels are shown
        c3_c4_active = analysis.get('channels_3_and_4_active', False)
        others_inactive = analysis.get('others_inactive', False)
        only_two = analysis.get('only_two_channels_visible', False)
        
        if c3_c4_active and others_inactive:
            score += 50
            feedback_parts.append("✅ Channels correctly isolated (3 & 4 only)")
        elif only_two:
            # Partial credit if 2 channels shown but maybe not specifically verified as 3/4 by VLM
            score += 40
            feedback_parts.append("✅ Two channels visible (assuming 3 & 4)")
        else:
            feedback_parts.append("❌ Channel isolation incorrect (must show ONLY channels 3 and 4)")
            
        # Check Data Streaming (10 pts)
        if analysis.get('data_streaming', False):
            score += 10
            feedback_parts.append("✅ Data appears to be streaming")
        else:
            feedback_parts.append("⚠️ Data stream may be paused or empty")

    except Exception as e:
        logger.error(f"VLM parsing error: {e}")
        feedback_parts.append("⚠️ automated visual verification failed")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }