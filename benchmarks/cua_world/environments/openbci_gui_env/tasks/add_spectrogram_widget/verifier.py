#!/usr/bin/env python3
"""
Verifier for add_spectrogram_widget task.
Uses VLM to verify the presence of the Spectrogram widget and Channel 2 selection.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_spectrogram_widget(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Started the session.
    2. Added a Spectrogram widget (2D heatmap).
    3. Selected Channel 2.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    if not query_vlm:
        return {"passed": False, "score": 0, "feedback": "VLM query function not available"}

    # 1. Load basic execution data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    score = 0
    feedback_parts = []
    
    # Check if app is running (10 pts)
    if result.get("app_running", False):
        score += 10
        feedback_parts.append("OpenBCI GUI is running.")
    else:
        feedback_parts.append("OpenBCI GUI is NOT running.")

    # 2. VLM Verification
    # We use a trajectory sampling to see the interaction, plus the final state.
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {"passed": False, "score": score, "feedback": "No final screenshot available."}
    
    # Combined prompt for efficiency, but asking for specific structured output
    prompt = """
    You are verifying an OpenBCI GUI task. The user was supposed to:
    1. Start a Synthetic session (data should be flowing/scrolling).
    2. Add a 'Spectrogram' widget to the dashboard (replacing another widget).
    3. Configure the Spectrogram widget to show 'Channel 2'.

    Look at the sequence of images, especially the final one.
    
    A Spectrogram widget looks like a 2D heatmap (frequency vs time) with colors (blue/green/red), typically scrolling vertically or horizontally. It is DISTINCT from a line plot (FFT) or waveform traces (Time Series).
    
    Answer the following in JSON format:
    {
        "session_active": true/false, // Is the 'Stop Session' button visible or data visibly scrolling?
        "spectrogram_visible": true/false, // Is there a 2D Time-Frequency Heatmap widget?
        "channel_2_selected": true/false, // Does the Spectrogram widget specifically say "Chan 2", "2", or "CH2"?
        "data_flowing": true/false, // Is the heatmap showing colored data (not just blank/black)?
        "reasoning": "Explain what you see regarding the widget type and channel selection"
    }
    """
    
    try:
        vlm_response = query_vlm(images=frames + [final_screenshot], prompt=prompt)
        analysis = vlm_response.get('parsed', {})
        
        # Scoring based on VLM analysis
        
        # Session Running (20 pts)
        if analysis.get("session_active", False):
            score += 20
            feedback_parts.append("Session appears active.")
        else:
            feedback_parts.append("Session does not appear active.")
            
        # Spectrogram Visible (35 pts)
        if analysis.get("spectrogram_visible", False):
            score += 35
            feedback_parts.append("Spectrogram widget (heatmap) detected.")
        else:
            feedback_parts.append("Spectrogram widget NOT detected.")
            
        # Channel 2 Selected (25 pts)
        if analysis.get("channel_2_selected", False):
            score += 25
            feedback_parts.append("Channel 2 selection confirmed.")
        else:
            feedback_parts.append("Channel 2 selection NOT confirmed (or not visible).")
            
        # Active Data Display (10 pts)
        if analysis.get("data_flowing", False):
            score += 10
            feedback_parts.append("Data appears to be flowing in the widget.")
        else:
            feedback_parts.append("Widget appears empty/blank.")
            
        feedback = " ".join(feedback_parts) + f" (VLM Reasoning: {analysis.get('reasoning', 'None')})"

    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback = f"VLM verification error: {str(e)}"
        # Fallback: if app is running and settings modified, give minimal credit? 
        # No, strict verification required for this visual task.

    # Final Pass Determination
    # Threshold: 55 points (Needs Session Running + Spectrogram Visible at minimum)
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }