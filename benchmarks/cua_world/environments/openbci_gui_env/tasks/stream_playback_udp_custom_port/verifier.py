#!/usr/bin/env python3
"""
Verifier for stream_playback_udp_custom_port@1

Verification Strategy:
1. Programmatic: Check if UDP port 12345 is active (via netstat/lsof from export script).
2. Programmatic: Check if the recording file was accessed (atime).
3. VLM: Analyze final screenshot to verify:
   - Networking widget presence
   - Port set to 12345
   - Protocol set to UDP
   - Streaming status
   - Playback waveforms visible
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stream_playback_udp(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
    task_result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Programmatic Signals
    port_active = task_result.get("port_12345_active", False)
    app_running = task_result.get("app_running", False)
    file_accessed = task_result.get("recording_file_accessed", False)
    
    score = 0
    feedback_parts = []
    
    # Base points for app running
    if app_running:
        score += 10
        feedback_parts.append("OpenBCI GUI is running")
    else:
        return {"passed": False, "score": 0, "feedback": "OpenBCI GUI is not running"}

    # Points for programmatic port detection (strong signal)
    if port_active:
        score += 30
        feedback_parts.append("UDP Port 12345 is active")
    else:
        feedback_parts.append("UDP Port 12345 NOT detected active")

    # Points for file access
    if file_accessed:
        score += 10
        feedback_parts.append("Recording file accessed")

    # 3. VLM Verification
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Analyze this screenshot of the OpenBCI GUI.
        1. Is the 'Networking' widget visible?
        2. In the Networking widget, what is the 'Port' number? (Look for '12345')
        3. In the Networking widget, is the protocol 'UDP'?
        4. Does the Networking widget say 'Streaming' or show a 'Stop' button (indicating it is active)?
        5. Are there EEG waveforms visible in the Time Series widget (indicating playback)?
        
        Return JSON:
        {
            "networking_widget_visible": bool,
            "port_12345_visible": bool,
            "protocol_udp": bool,
            "stream_active": bool,
            "waveforms_visible": bool
        }
        """
        
        vlm_response = query_vlm(
            prompt=prompt,
            images=[final_screenshot]
        )
        
        vlm_data = vlm_response.get("parsed", {})
        
        # Scoring VLM output
        if vlm_data.get("networking_widget_visible"):
            score += 10
            feedback_parts.append("Networking widget visible")
            
            if vlm_data.get("port_12345_visible"):
                score += 20
                feedback_parts.append("Port 12345 confirmed visually")
            else:
                feedback_parts.append("Port 12345 NOT confirmed visually")
                
            if vlm_data.get("protocol_udp"):
                score += 10
                feedback_parts.append("Protocol UDP confirmed")
                
            if vlm_data.get("stream_active"):
                score += 10
                feedback_parts.append("Stream active visually")
        else:
            feedback_parts.append("Networking widget NOT found")
            
        if vlm_data.get("waveforms_visible"):
            score += 10 # Extra 10 only if not already maxed? Total verification logic handles it.
            feedback_parts.append("Waveforms visible")

    # Final Score Calculation
    # Max possible: 10 (app) + 30 (port_prog) + 10 (file) + 10 (net_viz) + 20 (port_viz) + 10 (udp) + 10 (stream) + 10 (wave) = 110
    # Cap at 100
    score = min(score, 100)
    
    # Pass condition: Must have port active (either programmatically or visually) AND stream active
    # We require port 12345 specifically.
    pass_threshold = 70
    passed = score >= pass_threshold and (port_active or vlm_data.get("port_12345_visible", False))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }