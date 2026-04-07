#!/usr/bin/env python3
"""
Verifier for configure_ptz_camera_optics task.

Tests deeply nested node addition (Focus, Zoom) and precise physical parameter configuration
for a pipeline crawler's inspection camera.

Scoring (100 points total):
  - File saved at correct path and created during task: 10 points
  - Resolution (width 1920, height 1080) and base FOV (1.57): 20 points
  - Focus node added: 15 points
  - Focus parameters (focalLength 0.05, minFocalDistance 0.1, maxFocalDistance 10.0): 25 points
  - Zoom node added: 15 points
  - Zoom parameters (maxFieldOfView 1.57, minFieldOfView 0.157): 15 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_ptz_camera_optics(traj, env_info, task_info):
    """
    Verify the PTZ camera optics configuration was properly saved in the Webots world.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/ptz_inspection_camera.wbt')
    
    score = 0
    feedback_parts = []
    
    # --- Step 1: Check Export Result Metadata ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load task result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if not result.get('file_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Output file not found at {output_path}. Must save using File > Save World As."
        }
        
    if not result.get('file_created_during_task', False):
        feedback_parts.append("WARNING: File modification time is older than task start time. ")
    else:
        score += 10
        feedback_parts.append("World file saved correctly.")

    # --- Step 2: Extract and Parse .wbt File ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = ""

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)
            
    if not wbt_content or len(wbt_content) < 100:
        return {"passed": False, "score": score, "feedback": "Saved world file is empty or invalid."}

    # Extract camera block to ensure we are looking at the right scope
    camera_idx = wbt_content.find('Camera {')
    if camera_idx == -1:
        feedback_parts.append("Camera node is missing entirely.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # --- Step 3: Check Resolution & Base FOV (20 points) ---
    width_match = re.search(r'width\s+(\d+)', wbt_content)
    height_match = re.search(r'height\s+(\d+)', wbt_content)
    fov_match = re.search(r'fieldOfView\s+([\d.]+)', wbt_content)
    
    res_correct = 0
    if width_match and int(width_match.group(1)) == metadata.get('expected_width'):
        res_correct += 1
    if height_match and int(height_match.group(1)) == metadata.get('expected_height'):
        res_correct += 1
    if fov_match and abs(float(fov_match.group(1)) - metadata.get('expected_base_fov')) < 0.05:
        res_correct += 1
        
    if res_correct == 3:
        score += 20
        feedback_parts.append("Resolution and base FOV configured correctly.")
    else:
        feedback_parts.append("Resolution or base FOV is incorrect.")

    # --- Step 4: Check Focus Node & Params (40 points total) ---
    has_focus = bool(re.search(r'\bFocus\b\s*\{', wbt_content))
    if has_focus:
        score += 15
        feedback_parts.append("Focus node successfully added.")
        
        fl_match = re.search(r'focalLength\s+([\d.]+)', wbt_content)
        min_fd_match = re.search(r'minFocalDistance\s+([\d.]+)', wbt_content)
        max_fd_match = re.search(r'maxFocalDistance\s+([\d.]+)', wbt_content)
        
        focus_params = 0
        if fl_match and abs(float(fl_match.group(1)) - metadata.get('expected_focal_length')) < 0.01:
            focus_params += 1
        if min_fd_match and abs(float(min_fd_match.group(1)) - metadata.get('expected_min_focal_dist')) < 0.01:
            focus_params += 1
        if max_fd_match and abs(float(max_fd_match.group(1)) - metadata.get('expected_max_focal_dist')) < 0.1:
            focus_params += 1
            
        if focus_params == 3:
            score += 25
            feedback_parts.append("Focus parameters are perfectly matched.")
        else:
            score += (focus_params * 8)
            feedback_parts.append(f"Some Focus parameters incorrect ({focus_params}/3 correct).")
    else:
        feedback_parts.append("Focus node is missing.")

    # --- Step 5: Check Zoom Node & Params (30 points total) ---
    has_zoom = bool(re.search(r'\bZoom\b\s*\{', wbt_content))
    if has_zoom:
        score += 15
        feedback_parts.append("Zoom node successfully added.")
        
        max_fov_match = re.search(r'maxFieldOfView\s+([\d.]+)', wbt_content)
        min_fov_match = re.search(r'minFieldOfView\s+([\d.]+)', wbt_content)
        
        zoom_params = 0
        if max_fov_match and abs(float(max_fov_match.group(1)) - metadata.get('expected_max_fov')) < 0.05:
            zoom_params += 1
        if min_fov_match and abs(float(min_fov_match.group(1)) - metadata.get('expected_min_fov')) < 0.05:
            zoom_params += 1
            
        if zoom_params == 2:
            score += 15
            feedback_parts.append("Zoom range parameters are correctly matched.")
        else:
            score += (zoom_params * 7)
            feedback_parts.append(f"Some Zoom parameters incorrect ({zoom_params}/2 correct).")
    else:
        feedback_parts.append("Zoom node is missing.")

    # Evaluate final pass/fail
    passed = score >= 70 and has_focus and has_zoom
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }