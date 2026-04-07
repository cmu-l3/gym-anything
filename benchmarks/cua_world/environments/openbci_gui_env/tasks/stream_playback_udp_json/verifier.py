#!/usr/bin/env python3
"""
Verifier for stream_playback_udp_json task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stream_playback_udp_json(traj, env_info, task_info):
    """
    Verify that the agent configured UDP JSON streaming correctly.
    
    Checks:
    1. UDP packets were received by the background listener (from task_result.json).
    2. Packets were valid JSON.
    3. Packets contained non-zero EEG data (proving playback).
    4. VLM verifies widget settings in screenshots.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ============================================================
    # 1. Programmatic Verification (UDP Listener Results)
    # ============================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    packet_count = result.get('packet_count', 0)
    valid_json_count = result.get('valid_json_count', 0)
    has_eeg_data = result.get('has_eeg_data', False)

    # Criterion 1: Packets Received (Max 40 pts)
    if packet_count >= 5:
        score += 40
        feedback_parts.append(f"Received {packet_count} packets")
    elif packet_count > 0:
        score += 20
        feedback_parts.append(f"Received only {packet_count} packets (expected > 5)")
    else:
        feedback_parts.append("No UDP packets received on port 12345")

    # Criterion 2: Valid JSON (Max 20 pts)
    if valid_json_count >= 5:
        score += 20
        feedback_parts.append("Data format is valid JSON")
    elif valid_json_count > 0:
        score += 10
        feedback_parts.append("Some packets were JSON")
    elif packet_count > 0:
        feedback_parts.append("Packets received but NOT JSON (wrong format selected?)")

    # Criterion 3: Real Data (Max 20 pts)
    if has_eeg_data:
        score += 20
        feedback_parts.append("Payload contains active EEG data (Playback running)")
    elif packet_count > 0:
        feedback_parts.append("Packets received but data was all zeros (Playback not started?)")

    # ============================================================
    # 2. VLM Verification (Widget Settings) (Max 20 pts)
    # ============================================================
    # Only run VLM if we are missing points or need to confirm visual state
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = """
        Analyze this screenshot of the OpenBCI GUI.
        1. Is the 'Networking' widget visible?
        2. Is 'UDP' selected as the protocol?
        3. Is 'JSON' selected as the data type?
        4. Is the port number '12345' visible?
        5. Does the playback timeline (bottom of screen usually) show progress (not 00:00)?
        
        Answer with JSON: {"networking_visible": bool, "udp_selected": bool, "json_selected": bool, "port_correct": bool, "playback_active": bool}
        """
        
        try:
            vlm_response = query_vlm(
                prompt=prompt,
                images=[final_screenshot]
            )
            parsed = vlm_response.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('networking_visible'): vlm_score += 5
            if parsed.get('udp_selected'): vlm_score += 5
            if parsed.get('json_selected'): vlm_score += 5
            if parsed.get('port_correct'): vlm_score += 5
            
            score += vlm_score
            
            if vlm_score < 20:
                feedback_parts.append(f"VLM settings check partial pass: {parsed}")
            else:
                feedback_parts.append("VLM confirmed correct widget settings")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # If programmatic checks passed fully, give benefit of doubt for VLM
            if score >= 80:
                score += 20
                feedback_parts.append("VLM skipped (Programmatic success)")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }