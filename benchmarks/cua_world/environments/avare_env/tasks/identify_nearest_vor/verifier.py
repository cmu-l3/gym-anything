#!/usr/bin/env python3
"""
Verifier for identify_nearest_vor task.

Verifies that the agent:
1. Configured GPS simulation
2. Used the Nearest feature
3. Identified the correct VOR (MOD) for the location
4. Saved the data to the correct file format
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_nearest_vor(traj, env_info, task_info):
    """
    Verify the agent identified the nearest VOR correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vors = metadata.get('expected_vors', ['MOD', 'ECA'])
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve Artifacts
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Get result JSON
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Get result Text File (for backup/direct verification)
        # We rely on the content in JSON, but fetching file confirms it exists on disk for real
        file_exists_on_disk = False
        try:
            copy_from_env("/sdcard/nearest_vor_result.txt", temp_txt.name)
            file_exists_on_disk = True
        except Exception:
            pass
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    # ================================================================
    # 2. File & Content Verification (Programmatic) - 60 Points
    # ================================================================
    
    output_exists = result_data.get('output_exists', False)
    content = result_data.get('output_content', '')
    created_during_task = result_data.get('file_created_during_task', False)
    
    # Criteria A: File Creation (10 pts)
    if output_exists and file_exists_on_disk:
        score += 10
        feedback_parts.append("Result file created")
    else:
        feedback_parts.append("Result file NOT found")
        
    # Criteria B: Anti-gaming Timestamp (5 pts)
    if created_during_task:
        score += 5
        feedback_parts.append("File created during task window")
    elif output_exists:
        feedback_parts.append("Warning: File timestamp verification failed (stale file?)")

    # Criteria C: Content Parsing (45 pts)
    # Expected format:
    # IDENTIFIER: MOD
    # FREQUENCY: 114.60
    # DISTANCE: 15.0
    
    id_match = re.search(r'IDENTIFIER:\s*([A-Z]{3})', content, re.IGNORECASE)
    freq_match = re.search(r'FREQUENCY:\s*([0-9.]+)', content, re.IGNORECASE)
    dist_match = re.search(r'DISTANCE:\s*([0-9.]+)', content, re.IGNORECASE)
    
    found_id = id_match.group(1).upper() if id_match else None
    found_freq = float(freq_match.group(1)) if freq_match else None
    found_dist = float(dist_match.group(1)) if dist_match else None
    
    # Verify ID
    if found_id:
        if found_id in expected_vors:
            score += 15
            feedback_parts.append(f"Correct nearest VOR identified: {found_id}")
            
            # Verify Frequency for the specific VOR
            expected_freqs = {"MOD": 114.60, "ECA": 116.00, "PXN": 112.60}
            expected_f = expected_freqs.get(found_id)
            
            if found_freq and abs(found_freq - expected_f) < 0.1:
                score += 15
                feedback_parts.append(f"Correct frequency: {found_freq}")
            else:
                feedback_parts.append(f"Incorrect frequency for {found_id} (Expected {expected_f}, got {found_freq})")
        else:
            feedback_parts.append(f"Wrong VOR identified: {found_id} (Expected one of {expected_vors})")
    else:
        feedback_parts.append("Could not parse VOR Identifier")

    # Verify Distance (Sanity check)
    # From 37.4, -120.95:
    # MOD (37.62, -120.95) is ~13.5nm North
    # ECA is ~28nm North
    # PXN is ~40nm South
    # We accept reasonable ranges
    if found_dist is not None:
        if 5.0 <= found_dist <= 50.0:
            score += 15
            feedback_parts.append(f"Distance {found_dist}nm is reasonable")
        else:
            feedback_parts.append(f"Distance {found_dist}nm seems unrealistic for nearest VOR")
    else:
        feedback_parts.append("Could not parse Distance")

    # ================================================================
    # 3. Visual Trajectory Verification (VLM) - 40 Points
    # ================================================================
    
    # Sample frames to check workflow
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)
        
    vlm_prompt = """
    Review this sequence of screenshots from the Avare aviation app.
    I am looking for evidence of the following workflow:
    1. User accessing Preferences/Settings to enable 'Simulation Mode'.
    2. User setting a specific GPS location (Latitude/Longitude).
    3. User viewing the 'Nearest' screen/tab.
    4. User selecting 'Navaids' or 'VOR' category in the Nearest list.
    
    Return a JSON object with boolean keys:
    {
        "simulation_settings_accessed": boolean,
        "gps_location_input_visible": boolean,
        "nearest_screen_visible": boolean,
        "vor_navaids_listed": boolean
    }
    """
    
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        vlm_score = 0
        if parsed.get('simulation_settings_accessed', False) or parsed.get('gps_location_input_visible', False):
            vlm_score += 15
            feedback_parts.append("VLM: Simulation setup detected")
        
        if parsed.get('nearest_screen_visible', False):
            vlm_score += 15
            feedback_parts.append("VLM: Nearest screen visited")
            
        if parsed.get('vor_navaids_listed', False):
            vlm_score += 10
            feedback_parts.append("VLM: VOR list visible")
            
        score += vlm_score
        
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("VLM verification failed (technical error)")

    # ================================================================
    # Final Scoring
    # ================================================================
    
    passed = (score >= 60) and (found_id in expected_vors)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }