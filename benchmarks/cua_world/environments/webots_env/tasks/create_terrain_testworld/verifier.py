#!/usr/bin/env python3
"""
Verifier for create_terrain_testworld task.

This verifier rigorously parses the resulting Webots world file (.wbt) using 
`copy_from_env` to verify 3D geometries, hierarchical nodal configurations,
and physics boundaries.

Scoring (100 points total):
  - File exists and >500 bytes (anti-gaming): 5 points
  - ElevationGrid node present: 15 points
  - xDimension is 6: 10 points
  - zDimension is 6: 10 points
  - Height values form a hill (max height in range [0.5, 1.2]): 15 points
  - Spacing configuration correct (~2.0): 5 points
  - Pioneer3at robot node present: 15 points
  - Terrain boundingObject configured (for collision): 10 points
  - Terrain has Appearance/PBRAppearance: 10 points
  - DEF name TERRAIN correctly applied: 5 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_terrain_testworld(traj, env_info, task_info):
    """
    Copy the generated .wbt file from the environment and verify its semantic structure.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable - framework error."}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Desktop/terrain_nav_test.wbt')
    expected_x = metadata.get('expected_x_dimension', 6)
    expected_z = metadata.get('expected_z_dimension', 6)
    min_height = metadata.get('min_expected_height', 0.5)
    max_height = metadata.get('max_expected_height', 1.2)

    score = 0
    feedback_parts = []

    # 1. Retrieve the task export summary
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    try:
        copy_from_env('/tmp/task_result.json', temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        logger.warning(f"Could not read task export JSON: {e}")
        export_result = {}

    # Check anti-gaming
    if not export_result.get('file_created_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Task failed: File was not created/saved during this session (possible anti-gaming detection)."
        }

    # 2. Copy the actual .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(expected_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        try: os.unlink(wbt_file.name)
        except Exception: pass

    # --- Criterion 1: File Existence & Size (5 points) ---
    if not wbt_content or len(wbt_content) < 500:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed: Valid output file not found at {expected_path} or file is suspiciously empty."
        }
    score += 5
    feedback_parts.append("World file exists and meets size threshold")

    # --- Criterion 2: ElevationGrid Presence (15 points) ---
    has_grid = bool(re.search(r'ElevationGrid\s*\{', wbt_content))
    if has_grid:
        score += 15
        feedback_parts.append("ElevationGrid geometry present")
    else:
        feedback_parts.append("ElevationGrid geometry NOT found")

    # --- Criterion 3 & 4: Dimensions (20 points total) ---
    if has_grid:
        x_match = re.search(r'xDimension\s+(\d+)', wbt_content)
        if x_match and int(x_match.group(1)) == expected_x:
            score += 10
            feedback_parts.append("xDimension correct")
        else:
            feedback_parts.append("xDimension missing or incorrect")

        z_match = re.search(r'zDimension\s+(\d+)', wbt_content)
        if z_match and int(z_match.group(1)) == expected_z:
            score += 10
            feedback_parts.append("zDimension correct")
        else:
            feedback_parts.append("zDimension missing or incorrect")

    # --- Criterion 5: Hill Height Matrix (15 points) ---
    if has_grid:
        height_match = re.search(r'height\s+\[(.*?)\]', wbt_content, re.DOTALL)
        if height_match:
            # Extract all float values from the array
            height_str = height_match.group(1)
            heights = [float(x) for x in re.findall(r'[\d.-]+', height_str)]
            actual_max = max(heights) if heights else 0.0
            
            if min_height <= actual_max <= max_height:
                score += 15
                feedback_parts.append(f"Height array forms correct hill topology (max height: {actual_max})")
            elif actual_max == 0.0:
                feedback_parts.append("Height array is flat (all zeros) - expected hill profile")
            else:
                feedback_parts.append(f"Height profile incorrect (max height: {actual_max}, expected between {min_height} and {max_height})")
        else:
            feedback_parts.append("Height array missing or incorrectly formatted")

    # --- Criterion 6: Spacing (5 points) ---
    if has_grid:
        x_spacing = re.search(r'xSpacing\s+([\d.]+)', wbt_content)
        z_spacing = re.search(r'zSpacing\s+([\d.]+)', wbt_content)
        if x_spacing and z_spacing and 1.8 <= float(x_spacing.group(1)) <= 2.2:
            score += 5
            feedback_parts.append("Grid spacing correct")
        else:
            feedback_parts.append("Grid spacing missing or incorrect")

    # --- Criterion 7: Pioneer 3-AT Robot (15 points) ---
    has_robot = bool(re.search(r'Pioneer3at\s*\{', wbt_content)) or bool(re.search(r'Pioneer\s*3-AT', wbt_content))
    if has_robot:
        score += 15
        feedback_parts.append("Pioneer3at robot present")
    else:
        feedback_parts.append("Pioneer3at robot NOT found")

    # --- Criterion 8: boundingObject Collision Setup (10 points) ---
    # We check if boundingObject is assigned to a geometric node, USE reference, or group.
    has_bounds = bool(re.search(r'boundingObject\s+(USE|ElevationGrid|Shape|Transform|Group)', wbt_content))
    if has_bounds:
        score += 10
        feedback_parts.append("Terrain collision (boundingObject) configured")
    else:
        feedback_parts.append("boundingObject missing (terrain lacks collision)")

    # --- Criterion 9: Terrain Appearance (10 points) ---
    has_appearance = bool(re.search(r'(PBRAppearance|Appearance)\s*\{', wbt_content))
    if has_appearance:
        score += 10
        feedback_parts.append("Terrain appearance applied")
    else:
        feedback_parts.append("Appearance missing")

    # --- Criterion 10: DEF Name (5 points) ---
    has_def = bool(re.search(r'DEF\s+TERRAIN', wbt_content))
    if has_def:
        score += 5
        feedback_parts.append("DEF name 'TERRAIN' found")
    else:
        feedback_parts.append("DEF name 'TERRAIN' not found")

    # Assess overall pass criteria
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }