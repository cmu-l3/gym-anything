#!/usr/bin/env python3
"""
Verifier for stream_lsl_custom_name task.
Checks:
1. Programmatic confirmation that LSL stream "OpenBCI_Station_A" exists and is streaming data.
2. Visual confirmation via VLM that Networking widget is configured correctly.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stream_lsl_custom_name(traj, env_info, task_info):
    """
    Verify LSL streaming task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve programmatic results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract LSL verification data
    lsl_data = result_data.get("lsl_verification", {})
    stream_found = lsl_data.get("stream_found", False)
    data_received = lsl_data.get("data_received", False)
    found_streams = lsl_data.get("all_streams", [])
    app_running = result_data.get("app_running", False)

    score = 0
    feedback_parts = []

    # Scoring - Programmatic (70 points)
    if stream_found:
        score += 40
        feedback_parts.append("LSL stream 'OpenBCI_Station_A' detected (+40)")
    else:
        names = [s.get('name') for s in found_streams]
        feedback_parts.append(f"Target stream not found. Found: {names}")

    if data_received:
        score += 30
        feedback_parts.append("Data is actively streaming (+30)")
    elif stream_found:
        feedback_parts.append("Stream found but no data received (is playback started?)")

    # Scoring - Visual (30 points)
    # We use VLM to check if the UI looks correct, especially if programmatic check fails
    # or to confirm the method used.
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if final_frame:
        frames.append(final_frame)
        
        prompt = """
        Analyze these screenshots of the OpenBCI GUI.
        1. Is the "Networking" widget visible? (Look for a widget panel titled "Networking").
        2. In the Networking widget, is the Protocol set to "LSL"?
        3. Is the Name field in the Networking widget set to "OpenBCI_Station_A"?
        4. Does the Time Series widget show moving waveform data (lines not flat)?
        
        Respond in JSON:
        {
            "networking_widget_visible": bool,
            "protocol_is_lsl": bool,
            "name_is_correct": bool,
            "data_streaming_visible": bool
        }
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("networking_widget_visible"):
                    score += 5
                    feedback_parts.append("Networking widget visible (+5)")
                
                if parsed.get("protocol_is_lsl"):
                    score += 5
                    feedback_parts.append("Protocol is LSL (+5)")
                    
                if parsed.get("name_is_correct"):
                    score += 10
                    feedback_parts.append("Stream name visibly correct (+10)")
                    
                if parsed.get("data_streaming_visible"):
                    score += 10
                    feedback_parts.append("Waveforms visible (+10)")
                    
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback_parts.append("Visual verification skipped due to error")

    # Anti-gaming: If app wasn't running at end, penalty?
    # Actually, if app wasn't running, LSL check would fail anyway.
    
    passed = (score >= 70 and stream_found)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": "; ".join(feedback_parts)
    }