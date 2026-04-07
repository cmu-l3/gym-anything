#!/usr/bin/env python3
"""
Verifier for configure_dual_network_streams task.

Verification Strategy:
1. Primary: VLM analysis of the final state and agent's trajectory.
   - Verifies the Networking widget is visible.
   - Verifies Stream 1 is LSL/TimeSeries.
   - Verifies Stream 2 is OSC/BandPower/127.0.0.1/12345.
   - Verifies streams are active (Start button state).
2. Secondary: Programmatic checks from export_result.sh.
   - Checks if OpenBCI is running.
   - Checks if a screenshot was saved by the agent (as requested).
   - Checks for network port activity/settings files (bonus signal).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_dual_network_streams(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Programmatic Checks (30 points total)
    
    # Check if app is running (10 pts)
    if result.get('app_running', False):
        score += 10
        feedback.append("OpenBCI GUI is running.")
    else:
        feedback.append("OpenBCI GUI is NOT running.")

    # Check if agent took a screenshot (10 pts)
    if result.get('agent_screenshot_exists', False):
        score += 10
        feedback.append("Agent saved a screenshot as requested.")
    else:
        feedback.append("Agent did NOT save a screenshot.")

    # Check for OSC activity or settings match (10 pts bonus/confirmation)
    if result.get('osc_port_active', False) or result.get('settings_match', False):
        score += 10
        feedback.append("Confirmed OSC configuration via system/files.")
    
    # 3. VLM Verification (70 points total)
    # We use the final screenshot captured by the system (not the agent's)
    # to verify the actual state of the GUI.
    
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No final screenshot available for visual verification. " + " ".join(feedback)
        }

    # Prompt for VLM
    prompt = """
    Analyze this screenshot of the OpenBCI GUI.
    I need to verify if the 'Networking' widget is correctly configured with two streams.
    
    Look for a widget labeled 'Networking'.
    
    Check for Stream 1:
    - Protocol: LSL (Lab Streaming Layer)
    - Data Type: TimeSeries
    
    Check for Stream 2:
    - Protocol: OSC
    - Data Type: BandPower
    - IP: 127.0.0.1 (localhost)
    - Port: 12345
    
    Check Global Status:
    - Is the 'Start' button for the networking widget pressed/active (usually shows 'Stop' if running)?
    - Is the main 'Stop Data Stream' button visible in the top left (indicating the session is live)?

    Return a JSON object with these boolean keys:
    {
        "networking_widget_visible": true/false,
        "stream1_lsl_timeseries_correct": true/false,
        "stream2_osc_bandpower_correct": true/false,
        "stream2_ip_port_correct": true/false,
        "streams_active": true/false,
        "session_live": true/false
    }
    """

    try:
        vlm_response = query_vlm(
            images=[final_screenshot], 
            prompt=prompt
        )
        
        analysis = vlm_response.get('parsed', {})
        
        # Scoring VLM results
        if analysis.get('session_live', False):
            score += 10
            feedback.append("Session is live (streaming).")
        else:
            feedback.append("Session is NOT streaming.")

        if analysis.get('networking_widget_visible', False):
            score += 10
            feedback.append("Networking widget is visible.")
            
            # Detailed config checks only if widget is visible
            if analysis.get('stream1_lsl_timeseries_correct', False):
                score += 15
                feedback.append("Stream 1 (LSL/TimeSeries) configured correctly.")
            else:
                feedback.append("Stream 1 configuration incorrect.")

            if analysis.get('stream2_osc_bandpower_correct', False):
                score += 10
                feedback.append("Stream 2 (OSC/BandPower) protocol/type correct.")
            else:
                feedback.append("Stream 2 protocol/type incorrect.")

            if analysis.get('stream2_ip_port_correct', False):
                score += 10
                feedback.append("Stream 2 IP/Port (127.0.0.1:12345) correct.")
            else:
                feedback.append("Stream 2 IP/Port incorrect.")
                
            if analysis.get('streams_active', False):
                score += 15
                feedback.append("Network streams are active.")
            else:
                feedback.append("Network streams are NOT active.")

        else:
            feedback.append("Networking widget is NOT visible.")

    except Exception as e:
        feedback.append(f"VLM verification failed: {str(e)}")
        # Fallback: if we found programmatic evidence of OSC, give some partial credit
        if result.get('osc_port_active', False):
            score += 20
            feedback.append("Fallback: OSC port activity detected.")

    # Pass Threshold
    # Max score: 30 (programmatic) + 70 (VLM) = 100
    # Pass: 60
    passed = score >= 60

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }