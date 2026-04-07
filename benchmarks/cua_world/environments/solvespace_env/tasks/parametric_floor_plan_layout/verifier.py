#!/usr/bin/env python3
"""
Verifier for parametric_floor_plan_layout task.

Verifies:
1. File exists and was created during the task.
2. VLM trajectory shows L-shaped walls being drawn and constrained.
3. Parses the .slvs file to check geometry points and line segments.
4. Validates outer and inner L-shape topologies and coordinates.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if an agent successfully created a parametric architectural floor plan in SolveSpace.

TASK: Draw a 2D sketch of an L-shaped building perimeter with an inner wall loop uniformly offset by 150mm.

Look at these trajectory frames and determine:
1. Did the agent draw an L-shaped polygon?
2. Did the agent draw a second, nested L-shaped polygon inside the first one (resembling inner and outer walls)?
3. Did the agent apply dimensional constraints (numbers visible on the canvas, like 6000, 5000, 150, etc.)?

Respond ONLY in valid JSON format:
{
    "drew_l_shape": true/false,
    "drew_nested_walls": true/false,
    "applied_constraints": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

def parse_slvs_geometry(slvs_text):
    """Parses a plain-text .slvs file to extract line segments and points."""
    entities = {}
    current_entity = {}
    
    # Parse entities into dict
    for line in slvs_text.split('\n'):
        line = line.strip()
        if not line:
            if current_entity and 'h.v' in current_entity:
                entities[current_entity['h.v']] = current_entity
            current_entity = {}
            continue
        if line.startswith('Entity.'):
            try:
                key, val = line[7:].split('=', 1)
                current_entity[key] = val
            except ValueError:
                pass
                
    if current_entity and 'h.v' in current_entity:
        entities[current_entity['h.v']] = current_entity

    # Extract 2D/3D points and their solved coordinates
    points = {}
    for h_v, ent in entities.items():
        if ent.get('type') in ['2000', '2001', '2002', '2003', '2004']:
            try:
                x = float(ent.get('actPoint.x', 0))
                y = float(ent.get('actPoint.y', 0))
                points[h_v] = (x, y)
            except ValueError:
                pass

    # Extract Line Segments
    lines = []
    for h_v, ent in entities.items():
        if ent.get('type') == '11000':  # Line segment
            p0_id = ent.get('point[0].v')
            p1_id = ent.get('point[1].v')
            if p0_id in points and p1_id in points:
                lines.append((points[p0_id], points[p1_id]))
                
    return points, lines

def match_line_segment(actual_lines, expected_segment, tol=5.0):
    """Checks if an expected segment exists in the actual lines."""
    (ex1, ey1), (ex2, ey2) = expected_segment
    for (x1, y1), (x2, y2) in actual_lines:
        match_forward = (abs(x1 - ex1) <= tol and abs(y1 - ey1) <= tol and 
                         abs(x2 - ex2) <= tol and abs(y2 - ey2) <= tol)
        match_reverse = (abs(x1 - ex2) <= tol and abs(y1 - ey2) <= tol and 
                         abs(x2 - ex1) <= tol and abs(y2 - ey1) <= tol)
        if match_forward or match_reverse:
            return True
    return False

def verify_parametric_floor_plan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_outer_vertices = metadata.get('expected_outer_vertices')
    expected_inner_vertices = metadata.get('expected_inner_vertices')

    score = 0
    feedback_parts = []
    
    # 1. Retrieve JSON Result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic File Checks
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file was not saved to expected path"}
    if not file_created:
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during this task"}
    
    score += 15
    feedback_parts.append("File exists and created properly")

    # 2. Retrieve SLVS File
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env("/tmp/l_shape_floor_plan.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_text = f.read()
    except Exception as e:
        slvs_text = ""
        logger.error(f"Failed to read SLVS file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # 3. Geometric Verification
    points, lines = parse_slvs_geometry(slvs_text)
    
    # Build expected line segments from ordered vertices
    expected_outer_lines = [
        (expected_outer_vertices[i], expected_outer_vertices[(i+1)%6]) 
        for i in range(6)
    ]
    expected_inner_lines = [
        (expected_inner_vertices[i], expected_inner_vertices[(i+1)%6]) 
        for i in range(6)
    ]

    outer_matches = 0
    for ext_line in expected_outer_lines:
        if match_line_segment(lines, ext_line, tol=5.0):
            outer_matches += 1

    inner_matches = 0
    for int_line in expected_inner_lines:
        if match_line_segment(lines, int_line, tol=5.0):
            inner_matches += 1

    logger.info(f"Outer matches: {outer_matches}/6, Inner matches: {inner_matches}/6")

    geom_score = 0
    if outer_matches == 6:
        geom_score += 25
        feedback_parts.append("Exact outer perimeter coordinates found")
    elif outer_matches > 0:
        geom_score += (outer_matches * 3)
        feedback_parts.append(f"Partial outer perimeter matches ({outer_matches}/6)")
    else:
        feedback_parts.append("Outer perimeter coordinates missing or incorrect (not anchored to origin?)")

    if inner_matches == 6:
        geom_score += 25
        feedback_parts.append("Exact inner perimeter coordinates found")
    elif inner_matches > 0:
        geom_score += (inner_matches * 3)
        feedback_parts.append(f"Partial inner perimeter matches ({inner_matches}/6)")

    score += geom_score

    # Check for Constraints (distance values like 150, 6000)
    has_large_dim = "6000.0" in slvs_text or "5000.0" in slvs_text or "4000.0" in slvs_text
    has_thickness = "150.0" in slvs_text or "-150.0" in slvs_text
    
    if has_large_dim:
        score += 5
    if has_thickness:
        score += 5

    # 4. VLM Trajectory Verification
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
            
        vlm_res = query_vlm(prompt=VERIFICATION_PROMPT, images=frames)
        vlm_parsed = vlm_res.get('parsed', {})
        
        if vlm_parsed.get('drew_nested_walls') and vlm_parsed.get('applied_constraints'):
            score += 25
            feedback_parts.append("VLM confirmed nested walls with constraints")
        elif vlm_parsed.get('drew_l_shape'):
            score += 10
            feedback_parts.append("VLM confirmed L-shape drawn (missing inner walls or constraints)")
        else:
            feedback_parts.append("VLM did not detect correct drawing")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "outer_matches": outer_matches,
            "inner_matches": inner_matches,
            "has_thickness_constraint": has_thickness,
            "total_lines_found": len(lines)
        }
    }