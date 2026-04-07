#!/usr/bin/env python3
"""
Verifier for configure_tugger_solidreference task.

A logistics automation engineer must mechanically link a tugger robot to a material cart
using a SolidReference node, and configure the hitch's physical kinematic properties.

Scoring (100 points total):
  - File saved at correct path and created during task: 10 points
  - SolidReference instantiated with solidName "MATERIAL_CART": 30 points
  - Pivot Axis set to 0 0 1: 20 points
  - Anchor Point set to -1.2 0 0.15: 20 points
  - Joint Damping set to 2.5: 20 points

Pass threshold: 70 points
"""

import json
import re
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_tugger_solidreference(traj, env_info, task_info):
    """
    Verify that the tugger robot and cart have been mechanically linked and configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/tugger_linked.wbt')
    expected_solid_name = metadata.get('expected_solid_name', 'MATERIAL_CART')
    expected_axis = metadata.get('expected_axis', [0.0, 0.0, 1.0])
    expected_anchor = metadata.get('expected_anchor', [-1.2, 0.0, 0.15])
    expected_damping = metadata.get('expected_damping', 2.5)

    score = 0
    feedback_parts = []
    
    # --- Step 1: Read the export result JSON ---
    try:
        result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        result_file.close()
        copy_from_env('/tmp/configure_tugger_solidreference_result.json', result_file.name)
        with open(result_file.name) as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not read export result JSON: {e}")
        export_result = {}

    # --- Step 2: Copy and parse the .wbt file ---
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.warning(f"Could not copy .wbt file from VM: {e}")
        try:
            os.unlink(wbt_file.name)
        except Exception:
            pass

    # --- Step 3: Check file existence and anti-gaming ---
    file_exists = export_result.get('file_exists', False) and bool(wbt_content and len(wbt_content) > 100)
    file_created_during_task = export_result.get('file_created_during_task', True)
    
    if file_exists and file_created_during_task:
        score += 10
        feedback_parts.append("World file saved at correct path")
    elif file_exists:
        feedback_parts.append("World file exists but timestamp indicates it was not saved during the task")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Output file not found at {output_path}. You must save the world using File > Save World As."
        }

    # --- Step 4: Verify SolidReference Link ---
    solid_ref_match = re.search(r'SolidReference\s*\{[^\}]*solidName\s*"([^"]+)"', wbt_content)
    if solid_ref_match:
        actual_name = solid_ref_match.group(1)
        if actual_name == expected_solid_name:
            score += 30
            feedback_parts.append(f"SolidReference correctly linked to '{expected_solid_name}'")
        else:
            feedback_parts.append(f"SolidReference found, but linked to '{actual_name}' instead of '{expected_solid_name}'")
    else:
        feedback_parts.append("SolidReference with a solidName field not found inside the hitch joint.")

    # --- Step 5: Verify Pivot Axis ---
    axis_match = re.search(r'axis\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', wbt_content)
    if axis_match:
        ax_x, ax_y, ax_z = float(axis_match.group(1)), float(axis_match.group(2)), float(axis_match.group(3))
        if abs(ax_x - expected_axis[0]) < 0.01 and abs(ax_y - expected_axis[1]) < 0.01 and abs(ax_z - expected_axis[2]) < 0.01:
            score += 20
            feedback_parts.append("Pivot axis correctly set to Z-up (0 0 1)")
        else:
            feedback_parts.append(f"Pivot axis is set to {ax_x} {ax_y} {ax_z}, expected 0 0 1")
    else:
        feedback_parts.append("Axis field not found in the configured joint.")

    # --- Step 6: Verify Anchor Point ---
    anchor_match = re.search(r'anchor\s+([\d.-]+)\s+([\d.-]+)\s+([\d.-]+)', wbt_content)
    if anchor_match:
        an_x, an_y, an_z = float(anchor_match.group(1)), float(anchor_match.group(2)), float(anchor_match.group(3))
        if abs(an_x - expected_anchor[0]) < 0.01 and abs(an_y - expected_anchor[1]) < 0.01 and abs(an_z - expected_anchor[2]) < 0.01:
            score += 20
            feedback_parts.append(f"Anchor point correctly set to {expected_anchor[0]} {expected_anchor[1]} {expected_anchor[2]}")
        else:
            feedback_parts.append(f"Anchor point is set to {an_x} {an_y} {an_z}, expected {expected_anchor[0]} {expected_anchor[1]} {expected_anchor[2]}")
    else:
        feedback_parts.append("Anchor field not found in the configured joint.")

    # --- Step 7: Verify Joint Damping ---
    damping_match = re.search(r'dampingConstant\s+([\d.-]+)', wbt_content)
    if damping_match:
        actual_damping = float(damping_match.group(1))
        if abs(actual_damping - expected_damping) < 0.01:
            score += 20
            feedback_parts.append(f"Joint dampingConstant correctly set to {expected_damping}")
        else:
            feedback_parts.append(f"Joint dampingConstant is {actual_damping}, expected {expected_damping}")
    else:
        feedback_parts.append("dampingConstant field not found in the configured joint.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }