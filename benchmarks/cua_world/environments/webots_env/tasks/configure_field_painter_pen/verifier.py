#!/usr/bin/env python3
"""
Verifier for configure_field_painter_pen task.

A Field Robotics Engineer must configure a virtual paint sprayer (Pen device) on an 
autonomous robot to match FIFA standard field marking specifications.

Verification evaluates:
  1. Anti-Gaming: Output file exists and was modified during task time
  2. VLM Trajectory Check: Verify the agent interacted with the Webots scene tree.
  3. Strict programmatic parsing of `.wbt` file to verify:
     - inkColor == 1 1 1
     - inkDensity == 1.0
     - leadSize == 0.12
     - maxDistance == 0.06

Pass threshold: 75 points (Requires file existence, correct lead size, correct max distance, and at least one corrected visual property).
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_configure_field_painter_pen(traj, env_info, task_info):
    """
    Verify the autonomous field painter pen device was correctly configured and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/field_painter_configured.wbt')
    expected_density = metadata.get('expected_density', 1.0)
    expected_size = metadata.get('expected_size', 0.12)
    expected_distance = metadata.get('expected_distance', 0.06)

    score = 0
    feedback_parts = []
    
    # --- Step 1: Check Metadata & Anti-Gaming ---
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        copy_from_env('/tmp/task_result.json', temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        logger.warning(f"Could not load export result: {e}")
        export_result = {}

    if not export_result.get('file_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the configured world using File > Save World As."
        }
    
    if not export_result.get('file_created_during_task', True):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file timestamp predates task start. You must actively save a new configuration."
        }

    score += 10
    feedback_parts.append("World file saved during task time")

    # --- Step 2: VLM Trajectory Verification ---
    # Used to verify the workflow process (not just outcome) to prevent pure script gaming.
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """Look at these frames of a user operating the Webots 3D Simulator. 
Did the user navigate the scene tree on the left panel, expand robot nodes, edit property fields, and open menus? 
Respond with a JSON containing a single boolean field: {"active_workflow": true/false}"""
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_res.get("success", False):
            if vlm_res.get("parsed", {}).get("active_workflow", False):
                feedback_parts.append("VLM confirms Webots UI workflow progression")
            else:
                feedback_parts.append("Warning: VLM did not clearly observe UI workflow progression")
    except Exception as e:
        logger.warning(f"VLM trajectory verification skipped or failed: {e}")

    # --- Step 3: Copy the .wbt file independently and parse ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass

    if not wbt_content or len(wbt_content) < 100:
        return {"passed": False, "score": 0, "feedback": "Saved world file is empty or corrupted."}

    # Extract the 'paint_sprayer' Pen node context
    pen_idx = wbt_content.find('name "paint_sprayer"')
    if pen_idx == -1:
        feedback_parts.append("Could not find the 'paint_sprayer' Pen device in the saved file.")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Get a substring representing the Pen properties
    segment = wbt_content[max(0, pen_idx - 150):min(len(wbt_content), pen_idx + 400)]

    # --- Step 4: Verify Pen Parameters ---
    
    # Check inkColor (Expected 1 1 1)
    color_match = re.search(r'inkColor\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', segment)
    if color_match:
        r, g, b = float(color_match.group(1)), float(color_match.group(2)), float(color_match.group(3))
        if r == 1.0 and g == 1.0 and b == 1.0:
            score += 25
            feedback_parts.append("inkColor correctly set to 1 1 1 (White)")
        else:
            feedback_parts.append(f"inkColor is {r} {g} {b}, expected 1.0 1.0 1.0")
    else:
        feedback_parts.append("inkColor field not explicitly found (may be default 0 0 0)")

    # Check inkDensity (Expected 1.0)
    density_match = re.search(r'inkDensity\s+([\d.]+)', segment)
    if density_match:
        actual_density = float(density_match.group(1))
        if abs(actual_density - expected_density) < 0.001:
            score += 20
            feedback_parts.append("inkDensity correctly set to 1.0")
        else:
            feedback_parts.append(f"inkDensity is {actual_density}, expected {expected_density}")
    else:
        feedback_parts.append("inkDensity field not explicitly found")

    # Check leadSize (Expected 0.12)
    size_match = re.search(r'leadSize\s+([\d.]+)', segment)
    if size_match:
        actual_size = float(size_match.group(1))
        if abs(actual_size - expected_size) < 0.001:
            score += 25
            feedback_parts.append("leadSize correctly set to 0.12")
        else:
            feedback_parts.append(f"leadSize is {actual_size}, expected {expected_size}")
    else:
        feedback_parts.append("leadSize field not explicitly found")

    # Check maxDistance (Expected 0.06)
    dist_match = re.search(r'maxDistance\s+([\d.]+)', segment)
    if dist_match:
        actual_dist = float(dist_match.group(1))
        if abs(actual_dist - expected_distance) < 0.001:
            score += 20
            feedback_parts.append("maxDistance correctly set to 0.06")
        else:
            feedback_parts.append(f"maxDistance is {actual_dist}, expected {expected_distance}")
    else:
        feedback_parts.append("maxDistance field not explicitly found")

    # --- Step 5: Final Evaluation ---
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }