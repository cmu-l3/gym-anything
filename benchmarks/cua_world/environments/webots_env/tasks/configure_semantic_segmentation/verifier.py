#!/usr/bin/env python3
"""
Verifier for configure_semantic_segmentation task.

Scoring (100 points total):
  - File saved at correct path: 10 points
  - File created/modified during task timeframe: 10 points
  - Camera has Recognition node: 20 points
  - Recognition segmentation = TRUE: 20 points
  - Recognition maxRange = 15.0: 10 points
  - HAZMAT_BARREL has correct color [1, 0, 0]: 15 points
  - SHIPPING_CRATE has correct color [0, 0, 1]: 15 points

Pass threshold: 70 points
"""

import json
import re
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_color(block_content: str, expected_r: float, expected_g: float, expected_b: float) -> tuple[bool, str]:
    """Mathematically verify color to avoid regex floating point mismatches."""
    color_match = re.search(r'recognitionColors\s+\[\s*([\d\.]+)\s+([\d\.]+)\s+([\d\.]+)\s*\]', block_content)
    if color_match:
        try:
            r, g, b = map(float, color_match.groups())
            # Check within tight tolerance
            dist = abs(r - expected_r) + abs(g - expected_g) + abs(b - expected_b)
            if dist < 0.1:
                return True, f"Found correct color [{r}, {g}, {b}]"
            else:
                return False, f"Color mismatch: found [{r}, {g}, {b}], expected [{expected_r}, {expected_g}, {expected_b}]"
        except ValueError:
            return False, "Failed to parse color values."
    return False, "recognitionColors field not found."

def verify_configure_semantic_segmentation(traj, env_info, task_info):
    """
    Verify that the semantic segmentation configuration was correctly applied.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/semantic_dataset_configured.wbt')

    score = 0
    feedback_parts = []

    # --- Step 1: Read JSON exported metadata ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Validate output exists and timestamp
    output_exists = result.get('output_exists', False)
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. Save the world using File > Save World As."
        }
    
    score += 10
    feedback_parts.append("World file exists")

    if result.get('file_created_during_task', False):
        score += 10
        feedback_parts.append("File created/modified during task execution")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not saved during the task")

    # --- Step 2: Read VRML (.wbt) output file ---
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

    if len(wbt_content) < 100:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | Error: Output file is empty or corrupted."
        }

    # --- Step 3: Parse Camera Configuration ---
    cam_idx = wbt_content.find('name "vision_sensor"')
    if cam_idx != -1:
        # Extract surrounding context for the Camera node
        cam_block = wbt_content[cam_idx : cam_idx + 1000]
        
        has_recognition = 'Recognition {' in cam_block
        if has_recognition:
            score += 20
            feedback_parts.append("Recognition node added to Camera")
            
            # Check segmentation flag
            if re.search(r'segmentation\s+TRUE', cam_block):
                score += 20
                feedback_parts.append("Semantic segmentation enabled")
            else:
                feedback_parts.append("Segmentation flag is not TRUE")

            # Check maxRange parameter (matching 15 or 15.0)
            if re.search(r'maxRange\s+(15\.0|15\b)', cam_block):
                score += 10
                feedback_parts.append("maxRange properly set to 15.0")
            else:
                feedback_parts.append("maxRange is incorrect or missing")
        else:
            feedback_parts.append("Camera missing Recognition node")
    else:
        feedback_parts.append("Camera 'vision_sensor' not found in scene tree")

    # --- Step 4: Parse Semantic Colors ---
    # HAZMAT_BARREL (Target: Red [1, 0, 0])
    barrel_idx = wbt_content.find('DEF HAZMAT_BARREL Solid')
    if barrel_idx != -1:
        barrel_block = wbt_content[barrel_idx : barrel_idx + 1500]
        match, msg = check_color(barrel_block, 1.0, 0.0, 0.0)
        if match:
            score += 15
            feedback_parts.append("Hazmat Barrel color correct")
        else:
            feedback_parts.append(f"Hazmat Barrel: {msg}")
    else:
        feedback_parts.append("HAZMAT_BARREL node not found")

    # SHIPPING_CRATE (Target: Blue [0, 0, 1])
    crate_idx = wbt_content.find('DEF SHIPPING_CRATE Solid')
    if crate_idx != -1:
        crate_block = wbt_content[crate_idx : crate_idx + 1500]
        match, msg = check_color(crate_block, 0.0, 0.0, 1.0)
        if match:
            score += 15
            feedback_parts.append("Shipping Crate color correct")
        else:
            feedback_parts.append(f"Shipping Crate: {msg}")
    else:
        feedback_parts.append("SHIPPING_CRATE node not found")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }