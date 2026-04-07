#!/usr/bin/env python3
"""
Verifier for locate_eye_blink_artifact task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_locate_eye_blink_artifact(traj, env_info, task_info):
    """
    Verify the user correctly identified the timestamp of the first eye blink.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
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

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence (20 pts)
    if result.get('output_file_exists') and result.get('output_created_during_task'):
        score += 20
        feedback_parts.append("Timestamp file created.")
    elif result.get('output_file_exists'):
        score += 10
        feedback_parts.append("File exists but timestamp verification failed (pre-existing?).")
    else:
        feedback_parts.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Check Timestamp Accuracy (60 pts)
    user_time = result.get('user_timestamp', -1)
    gt_data = result.get('ground_truth', {})
    gt_time = gt_data.get('timestamp', -1)
    tolerance = task_info.get('metadata', {}).get('tolerance_seconds', 1.5)

    if user_time == -1:
        feedback_parts.append("Could not parse a valid number from file.")
    elif gt_time == -1:
        feedback_parts.append("Error calculating ground truth from data file.")
        # Fallback: if user provided a plausible positive number, give partial credit
        if user_time > 0 and user_time < 60:
            score += 30
            feedback_parts.append("Ground truth unavailable, accepted plausible value.")
    else:
        diff = abs(user_time - gt_time)
        if diff <= tolerance:
            score += 60
            feedback_parts.append(f"Timestamp correct ({user_time}s vs GT {gt_time:.2f}s).")
        elif diff <= (tolerance * 2):
            score += 30
            feedback_parts.append(f"Timestamp close but outside optimal range ({user_time}s vs GT {gt_time:.2f}s).")
        else:
            feedback_parts.append(f"Timestamp incorrect ({user_time}s vs GT {gt_time:.2f}s).")

    # 4. VLM Trajectory Verification (20 pts)
    # Check if they actually loaded the file and scrubbed/played
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an OpenBCI GUI task.
        The user should:
        1. Be in "PLAYBACK" mode (not Synthetic/Live).
        2. Have waveforms visible on screen (Time Series).
        3. Show evidence of interacting with the timeline (scrubbing) or pausing.
        
        Answer JSON:
        {
            "playback_mode_visible": true/false,
            "waveforms_visible": true/false,
            "timeline_interaction": true/false
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final], prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('playback_mode_visible') or parsed.get('waveforms_visible'):
                vlm_score += 10
            if parsed.get('timeline_interaction'):
                vlm_score += 10
                
            feedback_parts.append(f"VLM verification score: {vlm_score}/20")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Grant partial credit if programmatic checks passed strongly
            if score >= 80:
                vlm_score = 20
    else:
        # If VLM unavailable, grant points if timestamp was correct (hard to guess)
        if score >= 80:
            vlm_score = 20

    score += vlm_score

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }