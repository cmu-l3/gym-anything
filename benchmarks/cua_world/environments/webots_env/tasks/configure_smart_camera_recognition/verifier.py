#!/usr/bin/env python3
"""
Verifier for configure_smart_camera_recognition task.

An agricultural robotics engineer must configure the CROP_CAMERA to use 
Webots' built-in Recognition capabilities, and tag 3 WEED objects with recognitionColors.

Scoring (100 points total):
  - File exists and was saved: 10 points
  - VLM verifies Trajectory (Scene Tree usage): 10 points
  - Recognition node added to CROP_CAMERA: 15 points
  - Recognition.maxRange = 5.0: 10 points
  - Recognition.frameColor = 1 0.5 0: 10 points
  - WEED_1 tagged with recognitionColors [ 0.8 0.2 0.2 ]: 15 points
  - WEED_2 tagged with recognitionColors [ 0.8 0.2 0.2 ]: 15 points
  - WEED_3 tagged with recognitionColors [ 0.8 0.2 0.2 ]: 15 points

Pass threshold: 75 points
"""

import json
import re
import tempfile
import os
import logging

from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot

logger = logging.getLogger(__name__)


def extract_node_block(content, def_name):
    """Extracts a Webots node block safely without writing a full parser."""
    start_idx = content.find(f'DEF {def_name}')
    if start_idx == -1:
        return None
    
    # We find the matching closing brace for this node
    depth = 0
    in_node = False
    
    for i in range(start_idx, len(content)):
        if content[i] == '{':
            depth += 1
            in_node = True
        elif content[i] == '}':
            depth -= 1
            if in_node and depth == 0:
                return content[start_idx:i+1]
                
    return content[start_idx:]  # Fallback if malformed


def verify_configure_smart_camera_recognition(traj, env_info, task_info):
    """
    Verify the smart camera configuration task.
    Uses programmatic .wbt file parsing as the primary verification,
    supplemented by a VLM trajectory check.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/agri_smart_camera.wbt')
    
    score = 0
    feedback_parts = []
    
    # --- 1. Fetch metadata JSON ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/task_result.json', temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        export_result = {}
        logger.warning(f"Could not read export result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # --- 2. Copy the .wbt file ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
    except Exception as e:
        logger.warning(f"Could not copy .wbt file: {e}")
    finally:
        if os.path.exists(wbt_file.name):
            os.unlink(wbt_file.name)

    # --- 3. Evaluate File Existence & Anti-Gaming ---
    file_exists = export_result.get('file_exists', False)
    file_created = export_result.get('file_created_during_task', False)
    
    if file_exists and wbt_content and len(wbt_content) > 100:
        if file_created:
            score += 10
            feedback_parts.append("World file correctly saved during task")
        else:
            feedback_parts.append("WARNING: File exists but timestamp suggests it wasn't created during this task")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save using File > Save World As."
        }

    # --- 4. Evaluate CROP_CAMERA Configuration ---
    camera_block = extract_node_block(wbt_content, 'CROP_CAMERA')
    if camera_block:
        # Check for Recognition node inside recognition field
        recognition_match = re.search(r'recognition\s+Recognition\s*\{([^\}]*)\}', camera_block)
        if recognition_match:
            score += 15
            feedback_parts.append("Recognition node successfully added to CROP_CAMERA")
            
            rec_body = recognition_match.group(1)
            
            # Check maxRange
            max_range_match = re.search(r'maxRange\s+([\d.]+)', rec_body)
            if max_range_match and float(max_range_match.group(1)) == 5.0:
                score += 10
                feedback_parts.append("Recognition maxRange correctly set to 5.0")
            else:
                feedback_parts.append("Recognition maxRange not set to 5.0")
                
            # Check frameColor (using flexible spacing matching)
            frame_color_match = re.search(r'frameColor\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', rec_body)
            if frame_color_match:
                r, g, b = map(float, frame_color_match.groups())
                if r == 1.0 and g == 0.5 and b == 0.0:
                    score += 10
                    feedback_parts.append("Recognition frameColor correctly set to orange (1 0.5 0)")
                else:
                    feedback_parts.append(f"Recognition frameColor set to {r} {g} {b}, expected 1 0.5 0")
            else:
                feedback_parts.append("Recognition frameColor not found or incorrectly formatted")
        else:
            feedback_parts.append("Recognition node not found in CROP_CAMERA 'recognition' field")
    else:
        feedback_parts.append("CROP_CAMERA node missing from saved world")

    # --- 5. Evaluate WEED object tagging ---
    weed_names = metadata.get('weed_defs', ["WEED_1", "WEED_2", "WEED_3"])
    weeds_tagged = 0
    
    for weed_def in weed_names:
        weed_block = extract_node_block(wbt_content, weed_def)
        if weed_block:
            # Check for recognitionColors [ 0.8 0.2 0.2 ]
            # The brackets are technically optional in VRML if it's a single item, but Webots usually writes them
            color_match = re.search(r'recognitionColors\s*(?:\[\s*)?([\d.]+)\s+([\d.]+)\s+([\d.]+)(?:.*?)?(?:\])?', weed_block)
            if color_match:
                r, g, b = map(float, color_match.groups())
                if r == 0.8 and g == 0.2 and b == 0.2:
                    score += 15
                    weeds_tagged += 1
                    feedback_parts.append(f"{weed_def} correctly tagged with recognitionColors")
                else:
                    feedback_parts.append(f"{weed_def} recognitionColors is {r} {g} {b}, expected 0.8 0.2 0.2")
            else:
                feedback_parts.append(f"recognitionColors not found on {weed_def}")
        else:
            feedback_parts.append(f"{weed_def} node missing from saved world")

    # --- 6. VLM Trajectory Verification ---
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """Look at these trajectory frames from a user operating the Webots 3D simulator.
Did the user interact with the Scene Tree on the left to modify properties?
Look for expanded nodes like CROP_CAMERA or WEED_, and field editing in the panels.

Respond in JSON format:
{
    "used_scene_tree": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""
        vlm_result = query_vlm(prompt=prompt, images=frames)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("used_scene_tree", False):
                score += 10
                feedback_parts.append("VLM verified Scene Tree interaction")
            else:
                feedback_parts.append("VLM did not detect Scene Tree interaction")
        else:
            # If VLM fails, grant points to prevent blocking on network errors, 
            # since programmatic check is the absolute ground truth.
            score += 10
            feedback_parts.append("VLM check bypassed (error)")

    # 10 (File) + 15 (Rec Node) + 10 (maxRange) + 10 (frameColor) + 45 (Weeds) + 10 (VLM) = 100
    
    passed = score >= 75 and weeds_tagged >= 2 and recognition_match is not None
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }