#!/usr/bin/env python3
"""
Verifier for configure_ptz_camera_inspection task.

Validates that a Webots VRML file has been saved with correct:
- pan_motor position limits
- tilt_motor position limits
- Zoom node optics
- Focus node optics

Scoring (100 points total):
  - File exists & saved during task: 10 points
  - Pan Motor Limits: 20 points
  - Tilt Motor Limits: 20 points
  - Zoom Node Optics: 25 points
  - Focus Node Optics: 25 points

Pass threshold: 75 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def get_motor_limits(content, motor_name):
    """Helper to extract minPosition and maxPosition for a named motor."""
    # Find the motor declaration
    idx = content.find(f'name "{motor_name}"')
    if idx == -1:
        return None, None
    
    # Grab the block surrounding the motor definition
    start = max(0, idx - 100)
    end = min(len(content), idx + 200)
    block = content[start:end]
    
    min_match = re.search(r'minPosition\s+([\d.-]+)', block)
    max_match = re.search(r'maxPosition\s+([\d.-]+)', block)
    
    min_pos = float(min_match.group(1)) if min_match else None
    max_pos = float(max_match.group(1)) if max_match else None
    
    return min_pos, max_pos


def verify_configure_ptz_camera(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/ptz_crawler_configured.wbt')
    
    score = 0
    feedback_parts = []

    # 1. Read exported execution metadata
    result_meta = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/task_result.json', temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        os.unlink(temp_json.name)

    file_exists = result_meta.get('file_exists', False)
    file_modified = result_meta.get('file_modified_during_task', False)
    file_size = result_meta.get('file_size', 0)

    # Anti-gaming & basic existence
    if not file_exists or file_size < 500:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found or empty at {output_path}. Must save the world."
        }
    
    if not file_modified:
        feedback_parts.append("WARNING: File was not created/modified during task timeframe")
    else:
        score += 10
        feedback_parts.append("World file correctly saved during task")

    # 2. Copy the actual .wbt file for deep parsing
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
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

    if not wbt_content:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Failed to read .wbt file contents"
        }

    # 3. Check Pan Motor Limits
    pan_min, pan_max = get_motor_limits(wbt_content, "pan_motor")
    expected_pan_min, expected_pan_max = metadata.get('expected_pan_min', -1.57), metadata.get('expected_pan_max', 1.57)
    if pan_min is not None and pan_max is not None:
        if abs(pan_min - expected_pan_min) < 0.05 and abs(pan_max - expected_pan_max) < 0.05:
            score += 20
            feedback_parts.append("Pan motor limits correct")
        else:
            feedback_parts.append(f"Pan motor limits incorrect. Found min: {pan_min}, max: {pan_max}")
    else:
        feedback_parts.append("Pan motor limits not found")

    # 4. Check Tilt Motor Limits
    tilt_min, tilt_max = get_motor_limits(wbt_content, "tilt_motor")
    expected_tilt_min, expected_tilt_max = metadata.get('expected_tilt_min', -0.78), metadata.get('expected_tilt_max', 0.78)
    if tilt_min is not None and tilt_max is not None:
        if abs(tilt_min - expected_tilt_min) < 0.05 and abs(tilt_max - expected_tilt_max) < 0.05:
            score += 20
            feedback_parts.append("Tilt motor limits correct")
        else:
            feedback_parts.append(f"Tilt motor limits incorrect. Found min: {tilt_min}, max: {tilt_max}")
    else:
        feedback_parts.append("Tilt motor limits not found")

    # 5. Check Zoom Node
    zoom_block = re.search(r'Zoom\s*\{([^}]*)\}', wbt_content)
    expected_zmax, expected_zmin = metadata.get('expected_zoom_max', 0.87), metadata.get('expected_zoom_min', 0.087)
    if zoom_block:
        z_content = zoom_block.group(1)
        max_fov = re.search(r'maxFieldOfView\s+([\d.-]+)', z_content)
        min_fov = re.search(r'minFieldOfView\s+([\d.-]+)', z_content)
        
        if max_fov and min_fov:
            v_max, v_min = float(max_fov.group(1)), float(min_fov.group(1))
            if abs(v_max - expected_zmax) < 0.01 and abs(v_min - expected_zmin) < 0.01:
                score += 25
                feedback_parts.append("Zoom node configured correctly")
            else:
                feedback_parts.append(f"Zoom node values incorrect. Found max: {v_max}, min: {v_min}")
        else:
            feedback_parts.append("Zoom node missing minFieldOfView or maxFieldOfView")
    else:
        feedback_parts.append("Zoom node not found")

    # 6. Check Focus Node
    focus_block = re.search(r'Focus\s*\{([^}]*)\}', wbt_content)
    expected_fmin, expected_fmax = metadata.get('expected_focus_min', 0.5), metadata.get('expected_focus_max', 50.0)
    if focus_block:
        f_content = focus_block.group(1)
        min_fd = re.search(r'minFocalDistance\s+([\d.-]+)', f_content)
        max_fd = re.search(r'maxFocalDistance\s+([\d.-]+)', f_content)
        
        if min_fd and max_fd:
            v_min, v_max = float(min_fd.group(1)), float(max_fd.group(1))
            if abs(v_min - expected_fmin) < 0.1 and abs(v_max - expected_fmax) < 0.1:
                score += 25
                feedback_parts.append("Focus node configured correctly")
            else:
                feedback_parts.append(f"Focus node values incorrect. Found min: {v_min}, max: {v_max}")
        else:
            feedback_parts.append("Focus node missing minFocalDistance or maxFocalDistance")
    else:
        feedback_parts.append("Focus node not found")

    # Optionally run VLM over trajectory to ensure Webots UI was used
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            vlm_prompt = (
                "Look at these screenshots from a session. Did the user operate the Webots 3D simulator UI "
                "to interact with the scene tree and edit node properties? "
                "Answer yes or no."
            )
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res and "yes" in vlm_res.get("response", "").lower():
                feedback_parts.append("VLM confirms Webots UI usage")
            else:
                feedback_parts.append("VLM could not confirm Webots UI usage")
    except Exception as e:
        logger.info(f"VLM check skipped or failed: {e}")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }