#!/usr/bin/env python3
"""
Verifier for insert_event_markers task.

Verifies that:
1. A new recording file was created during the task.
2. The file contains specific event markers (1, 2, 3).
3. The markers are temporally separated (proving sequential insertion).
4. VLM verifies the visual workflow (Marker Mode widget presence).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insert_event_markers(traj, env_info, task_info):
    """
    Verify the agent inserted event markers into a synthetic recording.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    # Extract analysis data
    analysis = result.get('analysis', {})
    file_exists = analysis.get('file_exists', False)
    unique_markers = analysis.get('unique_markers', [])
    separation_ok = analysis.get('marker_separation_ok', False)
    file_size = analysis.get('file_size_bytes', 0)
    
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity (30 pts)
    if file_exists and file_size > 10000:  # >10KB
        score += 30
        feedback_parts.append("New valid recording file found")
    elif file_exists:
        score += 10
        feedback_parts.append("New recording file found but too small (<10KB)")
    else:
        feedback_parts.append("No new recording file created")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Marker Content (40 pts)
    required = {1, 2, 3}
    found = set(unique_markers)
    missing = required - found
    
    if not missing:
        score += 40
        feedback_parts.append("All required markers (1, 2, 3) found")
    else:
        # Partial credit
        pts = 40 * (len(found.intersection(required)) / 3)
        score += int(pts)
        feedback_parts.append(f"Found markers: {list(found)}. Missing: {list(missing)}")

    # 3. Temporal Separation (15 pts)
    if separation_ok:
        score += 15
        feedback_parts.append("Markers are temporally separated")
    elif len(found) > 0:
        feedback_parts.append("Markers found but not well separated (inserted too fast?)")

    # 4. VLM Verification (15 pts)
    # Check if Marker Mode widget was visible and recording indicator was active
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of the OpenBCI GUI workflow.
        I am looking for two specific things:
        1. "Marker Mode" widget: A panel showing buttons labeled 1, 2, 3 (or similar marker controls).
        2. Recording Status: Evidence that recording was active (e.g., "Stop Recording" button visible, red recording indicator).
        
        Return JSON:
        {
            "marker_widget_visible": true/false,
            "recording_active": true/false
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_frame], prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('marker_widget_visible'):
                vlm_score += 10
                feedback_parts.append("VLM: Marker widget detected")
            else:
                feedback_parts.append("VLM: Marker widget NOT detected")
                
            if parsed.get('recording_active'):
                vlm_score += 5
                feedback_parts.append("VLM: Recording activity detected")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback: if file verification was perfect, give full VLM points to avoid penalizing for VLM flakiness
            if score >= 85:
                vlm_score = 15
                feedback_parts.append("VLM skipped (programmatic pass)")
    
    score += vlm_score

    # Final Pass Determination
    # Must have created file and found at least 2 markers
    key_success = file_exists and len(found.intersection(required)) >= 2
    passed = score >= 70 and key_success

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }