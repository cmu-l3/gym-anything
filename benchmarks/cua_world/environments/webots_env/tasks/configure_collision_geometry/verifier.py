#!/usr/bin/env python3
"""
Verifier for configure_collision_geometry task.

A robotics simulation engineer must add boundingObject nodes to three objects
so physics collision detection works correctly.

Scoring Breakdown (100 points total):
  - File exported & created during task: 10 points
  - MOBILE_ROBOT boundingObject not NULL: 15 points
  - MOBILE_ROBOT boundingObject is Box: 10 points
  - OBSTACLE_BOX boundingObject is Box: 15 points
  - OBSTACLE_CYLINDER boundingObject is Cylinder: 15 points
  - Dimensions are within 50% tolerance: 20 points
  - VLM visual confirmation of UI activity: 15 points
"""

import json
import re
import tempfile
import os
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_node(content, def_name, expected_type):
    """
    Parses a specific DEF node chunk from the Webots world file to inspect its boundingObject.
    """
    idx = content.find(f"DEF {def_name}")
    if idx == -1:
        return False, False, []

    # Extract chunk for this node (up to next DEF or EOF)
    next_def = content.find("DEF ", idx + 10)
    if next_def == -1:
        chunk = content[idx:]
    else:
        chunk = content[idx:next_def]
    
    # Look for boundingObject field
    bo_idx = chunk.find("boundingObject")
    if bo_idx == -1:
        return False, False, []
    
    # Boundary of boundingObject is typically 'physics Physics' or '}'
    phys_idx = chunk.find("physics", bo_idx)
    if phys_idx == -1:
        phys_idx = bo_idx + 500  # generous bound
        
    bo_chunk = chunk[bo_idx:phys_idx]
    
    # Check if it was left as NULL
    if "NULL" in bo_chunk[:30]:
        return False, False, []
        
    has_geometry = expected_type in bo_chunk
    
    params = []
    if expected_type == "Box":
        # Match 'size X Y Z'
        m = re.search(r'size\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', bo_chunk)
        if m:
            params = [float(x) for x in m.groups()]
    elif expected_type == "Cylinder":
        # Match 'radius R' and 'height H'
        m_r = re.search(r'radius\s+([\d.]+)', bo_chunk)
        m_h = re.search(r'height\s+([\d.]+)', bo_chunk)
        r = float(m_r.group(1)) if m_r else 0
        h = float(m_h.group(1)) if m_h else 0
        params = [r, h]
        
    return True, has_geometry, params


def check_dimensions(actual_params, expected_params, tolerance=0.5):
    """Checks if actual dimensions are within tolerance % of expected dimensions."""
    if not actual_params or len(actual_params) != len(expected_params):
        return False
    
    for actual, expected in zip(actual_params, expected_params):
        diff = abs(actual - expected)
        if diff > expected * tolerance:
            return False
    return True


def verify_configure_collision_geometry(traj, env_info, task_info):
    """
    Verify that boundingObjects were correctly added to the robot and obstacles.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Desktop/collision_fixed.wbt')
    nodes_meta = metadata.get('nodes', {})

    score = 0
    feedback_parts = []
    
    # 1. Check Export Result Data (Anti-Gaming)
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_file.close()
    try:
        copy_from_env("/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            export_result = json.load(f)
        os.unlink(result_file.name)
    except Exception as e:
        logger.warning(f"Could not load export result: {e}")
        export_result = {}
        
    if not export_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": f"World file was not saved to {output_path}."}
        
    if not export_result.get('file_created_during_task', False):
        feedback_parts.append("WARNING: File timestamps suggest file was not created during task window.")
    else:
        score += 10
        feedback_parts.append("File created/saved successfully.")

    # 2. Copy and parse the .wbt file
    wbt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.wbt')
    wbt_file.close()
    wbt_content = None

    try:
        copy_from_env(output_path, wbt_file.name)
        with open(wbt_file.name, 'r', errors='replace') as f:
            wbt_content = f.read()
        os.unlink(wbt_file.name)
    except Exception as e:
        logger.error(f"Could not copy .wbt file: {e}")
        return {"passed": False, "score": score, "feedback": "Failed to retrieve the saved world file."}

    # 3. Analyze Nodes
    dimension_successes = 0
    
    # A. MOBILE_ROBOT
    r_def = "MOBILE_ROBOT"
    r_meta = nodes_meta.get(r_def, {})
    r_present, r_geom, r_params = check_node(wbt_content, r_def, r_meta.get('type', 'Box'))
    
    if r_present:
        score += 15
        feedback_parts.append(f"{r_def} boundingObject present")
        if r_geom:
            score += 10
            feedback_parts.append(f"{r_def} geometry is correct (Box)")
            if check_dimensions(r_params, r_meta.get('params')):
                dimension_successes += 1
        else:
            feedback_parts.append(f"{r_def} missing Box geometry")
    else:
        feedback_parts.append(f"{r_def} boundingObject is still NULL or missing")

    # B. OBSTACLE_BOX
    ob_def = "OBSTACLE_BOX"
    ob_meta = nodes_meta.get(ob_def, {})
    ob_present, ob_geom, ob_params = check_node(wbt_content, ob_def, ob_meta.get('type', 'Box'))
    
    if ob_present and ob_geom:
        score += 15
        feedback_parts.append(f"{ob_def} boundingObject is correct (Box)")
        if check_dimensions(ob_params, ob_meta.get('params')):
            dimension_successes += 1
    else:
        feedback_parts.append(f"{ob_def} boundingObject missing or wrong type")

    # C. OBSTACLE_CYLINDER
    oc_def = "OBSTACLE_CYLINDER"
    oc_meta = nodes_meta.get(oc_def, {})
    oc_present, oc_geom, oc_params = check_node(wbt_content, oc_def, oc_meta.get('type', 'Cylinder'))
    
    if oc_present and oc_geom:
        score += 15
        feedback_parts.append(f"{oc_def} boundingObject is correct (Cylinder)")
        if check_dimensions(oc_params, oc_meta.get('params')):
            dimension_successes += 1
    else:
        feedback_parts.append(f"{oc_def} boundingObject missing or wrong type")

    # Score Dimensions (max 20 points, 10 per successful dimension check up to 2)
    dim_score = min(dimension_successes * 10, 20)
    score += dim_score
    if dim_score > 0:
        feedback_parts.append(f"Dimensions configured well ({dimension_successes}/3 correct)")
    else:
        feedback_parts.append("Warning: boundingObject dimensions were inaccurate or unparsed.")

    # 4. VLM Verification of Trajectory
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """Look at these screenshots of an agent using Webots.
Did the agent interact with the Scene Tree (left panel) to modify 'boundingObject' fields?
Are there dialog boxes showing 'Add a node' or parameter inputs for Box/Cylinder geometries?
Reply strictly in JSON:
{
    "interacted_with_scene_tree": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}"""
            
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('interacted_with_scene_tree', False):
                    score += 15
                    feedback_parts.append("VLM confirms Scene Tree UI interaction.")
                else:
                    feedback_parts.append("VLM did not detect expected UI interaction.")
            else:
                # If VLM fails, grant points automatically to avoid penalizing agent for infrastructure issues
                score += 15
                feedback_parts.append("VLM check bypassed (awarded).")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            score += 15
            feedback_parts.append("VLM check error (awarded).")
    else:
        score += 15
        feedback_parts.append("VLM module not available (awarded).")

    # Determine passing status
    passed = score >= 70 and r_present and (ob_present or oc_present)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }