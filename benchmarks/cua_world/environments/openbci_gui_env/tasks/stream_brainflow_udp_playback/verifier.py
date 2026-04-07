#!/usr/bin/env python3
"""
Verifier for stream_brainflow_udp_playback task.

Criteria:
1. UDP packets received on port 9000 (Primary metric)
2. Data volume sufficient (> 50 packets) (Ensures streaming happened)
3. Data format is Binary/BrainFlow (NOT JSON) (Ensures correct Streamer vs Networking Widget used)
4. VLM verifies 'Playback' mode and correct file selection
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stream_brainflow_udp_playback(traj, env_info, task_info):
    """Verify UDP streaming of playback data."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ============================================================
    # 1. Load Programmatic Results (UDP Stats)
    # ============================================================
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

    packet_count = result.get('packet_count', 0)
    is_json = result.get('is_json', False)
    is_binary = result.get('is_binary', False)
    
    score = 0
    feedback_parts = []
    
    # Criterion 1 & 2: Data Flow (50 points)
    if packet_count > 50:
        score += 50
        feedback_parts.append(f"Streaming detected ({packet_count} packets)")
    elif packet_count > 0:
        score += 25
        feedback_parts.append(f"Weak streaming detected ({packet_count} packets)")
    else:
        feedback_parts.append("No UDP packets received on port 9000")
    
    # Criterion 3: Protocol Correctness (20 points)
    # BrainFlow Streamer sends binary. Networking Widget sends JSON.
    if packet_count > 0:
        if is_binary and not is_json:
            score += 20
            feedback_parts.append("Correct protocol (Binary/BrainFlow)")
        elif is_json:
            feedback_parts.append("Incorrect protocol (JSON detected - used Networking Widget instead of Streamer)")
        else:
            # Fallback for ambiguous data
            score += 10
            feedback_parts.append("Protocol format uncertain")
    
    # ============================================================
    # 2. VLM Verification (30 points)
    # ============================================================
    # Check if they actually used Playback mode and loaded the right file
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    images_to_check = frames + [final_shot] if final_shot else frames
    
    if not images_to_check:
        feedback_parts.append("No screenshots available for VLM")
    else:
        prompt = """
        Review these screenshots of the OpenBCI GUI.
        1. Is the data source set to 'PLAYBACK' (or 'File')? Look for 'PLAYBACK' in the Control Panel or 'Playback' text in the GUI.
        2. Is the loaded file named 'OpenBCI-EEG-S001-EyesOpen' (or similar)?
        3. Are the waveforms moving/scrolling (indicating active playback)?
        
        Return JSON:
        {
            "playback_mode_selected": true/false,
            "correct_file_loaded": true/false,
            "waveforms_active": true/false
        }
        """
        
        try:
            vlm_out = query_vlm(images=images_to_check, prompt=prompt)
            parsed = vlm_out.get('parsed', {})
            
            if parsed.get('playback_mode_selected'):
                score += 15
                feedback_parts.append("VLM confirmed Playback mode")
            else:
                feedback_parts.append("VLM did not see Playback mode selection")
                
            if parsed.get('correct_file_loaded'):
                score += 15
                feedback_parts.append("VLM confirmed correct file loaded")
            else:
                feedback_parts.append("VLM did not confirm correct file")
                
        except Exception as e:
            feedback_parts.append(f"VLM check failed: {str(e)}")

    # ============================================================
    # Final Scoring
    # ============================================================
    # Pass if we got significant binary data (programmatic proof is strongest)
    # OR if we got some data + visual confirmation
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }