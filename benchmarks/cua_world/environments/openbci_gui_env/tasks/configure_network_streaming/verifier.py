#!/usr/bin/env python3
"""
Verifier for configure_network_streaming task.

Verification Strategy:
1. File Check: Did the agent create the requested screenshot? (Anti-gaming)
2. Port Check: Is UDP port 12345 open? (Strong evidence of OSC stream start)
3. VLM Check: Analyze the final system screenshot to verify:
   - Networking widget is visible
   - Stream 1 is LSL / TimeSeries
   - Stream 2 is OSC / FFT / 127.0.0.1 / 12345
   - "Stop" button is visible (implying streams are running)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_network_streaming(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Extract Basic Signals
    app_running = result.get("app_running", False)
    screenshot_exists = result.get("agent_screenshot_exists", False)
    screenshot_valid = result.get("agent_screenshot_valid", False)
    osc_port_open = result.get("osc_port_12345_open", False)

    score = 0
    feedback_parts = []

    # 3. Score Basic Criteria (30 points)
    if app_running:
        score += 5
    else:
        feedback_parts.append("OpenBCI GUI was closed")

    if screenshot_exists and screenshot_valid:
        score += 15
        feedback_parts.append("Agent screenshot created")
    elif screenshot_exists:
        score += 5
        feedback_parts.append("Agent screenshot exists but timestamp invalid (pre-existing?)")
    else:
        feedback_parts.append("No screenshot created by agent")

    if osc_port_open:
        score += 10
        feedback_parts.append("UDP Port 12345 is open (OSC active)")
    else:
        feedback_parts.append("UDP Port 12345 NOT open")

    # 4. VLM Verification (70 points)
    # We use the system-captured screenshot from export_result.sh, or trajectory final frame
    # Ideally, we verify the screen state independent of the agent's screenshot file content
    final_screenshot = get_final_screenshot(traj)
    
    if not final_screenshot:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "No trajectory screenshot available for VLM verification. " + "; ".join(feedback_parts)
        }

    # Define VLM Prompt
    prompt = """
    Analyze this OpenBCI GUI screenshot.
    I need to verify the 'Networking' widget configuration.
    
    Please check for the following SPECIFIC details:
    1. Is the 'Networking' widget visible? (Look for a panel titled 'Networking')
    2. Are there two streams configured?
    3. Stream 1 Protocol: Is it 'LSL'?
    4. Stream 1 Data Type: Is it 'TimeSeries'?
    5. Stream 2 Protocol: Is it 'OSC'?
    6. Stream 2 Data Type: Is it 'FFT'?
    7. Stream 2 IP: Is it '127.0.0.1'?
    8. Stream 2 Port: Is it '12345'?
    9. Is the streaming active? (Look for a 'Stop' button, indicating it's currently running, or 'Start' if stopped).
    
    Return JSON with boolean keys:
    networking_visible, lsl_protocol_correct, lsl_type_correct, osc_protocol_correct, osc_type_correct, osc_ip_correct, osc_port_correct, streaming_active.
    """

    vlm_response = query_vlm(
        prompt=prompt,
        images=[final_screenshot],
        model="gpt-4o" # or default
    )

    vlm_data = vlm_response.get("parsed", {})
    if not vlm_data:
        # Fallback if parsing fails
        feedback_parts.append("VLM analysis failed to parse")
    else:
        # Scoring VLM components
        if vlm_data.get("networking_visible", False):
            score += 10
            feedback_parts.append("Networking widget visible")
        
        if vlm_data.get("lsl_protocol_correct", False):
            score += 10
        if vlm_data.get("lsl_type_correct", False):
            score += 5
            
        if vlm_data.get("osc_protocol_correct", False):
            score += 10
        if vlm_data.get("osc_type_correct", False):
            score += 5
            
        # Strict on IP/Port
        if vlm_data.get("osc_ip_correct", False) and vlm_data.get("osc_port_correct", False):
            score += 20
            feedback_parts.append("OSC IP/Port correct")
        elif vlm_data.get("osc_port_correct", False):
            score += 10
            feedback_parts.append("OSC Port correct, IP wrong")
        
        if vlm_data.get("streaming_active", False):
            score += 10
            feedback_parts.append("Streaming appears active")

    # 5. Final Evaluation
    passed = score >= 60 and osc_port_open
    
    # If port check failed but VLM says streaming is active, we might trust VLM slightly less
    # or assume the port check failed due to container networking oddities.
    # However, port check is ground truth.
    if not osc_port_open and vlm_data.get("streaming_active", False):
        feedback_parts.append("Warning: Visuals say streaming, but port 12345 is closed.")
        # We penalize passing if port is closed
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }