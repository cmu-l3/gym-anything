#!/usr/bin/env python3
"""
Verifier for warren_truss_2d_layout task.
Parses the SolveSpace .slvs file to mathematically guarantee that the parametric solver
resolved the constraints into the correct topological and geometric structure.
Also utilizes VLM on trajectory to verify work.
"""

import os
import json
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying if a computer agent successfully modeled a 2D Warren truss in CAD.

Examine these trajectory frames and the final screenshot. 
Does the agent successfully draw a 3-bay Warren truss?
Look for:
- A horizontal straight bottom chord
- A horizontal straight top chord, centered above the bottom chord
- Zig-zag diagonal members connecting them, forming a series of adjacent triangles (5 triangles total)
- The structure should appear as a fully connected wireframe

Respond in JSON format:
{
    "shows_warren_truss": true/false,
    "is_connected_wireframe": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is seen in the CAD canvas."
}
"""

def parse_slvs_file(filepath):
    """Robust text parser for SolveSpace .slvs format"""
    entities = {}
    constraints = []
    current_item = {}
    
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                
                if line.startswith('Entity.') or line.startswith('Constraint.'):
                    if '=' in line:
                        key, val = line.split('=', 1)
                        current_item[key] = val
                elif line == 'AddEntity':
                    if 'Entity.h.v' in current_item:
                        entities[current_item['Entity.h.v']] = current_item
                    current_item = {}
                elif line == 'AddConstraint':
                    constraints.append(current_item)
                    current_item = {}
                elif line.startswith('Add'):  # Catch AddGroup, AddParam, etc.
                    current_item = {}
    except Exception as e:
        logger.error(f"Error parsing slvs file: {e}")
        
    return entities, constraints

def verify_warren_truss(traj, env_info, task_info):
    """
    Verify the SLVS file constraints and topology + VLM verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Validate output file presence and anti-gaming
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output .slvs file not found. Task not completed."}
        
    if not result.get('file_modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp predates task start. Invalid submission."}

    if result.get('file_size_bytes', 0) < 500:
        return {"passed": False, "score": 0, "feedback": "Output file is too small to contain valid geometry."}

    score += 10
    feedback_parts.append("File created successfully")

    # 2. Parse SLVS File
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env("/tmp/warren_truss.slvs", temp_slvs.name)
        entities, constraints = parse_slvs_file(temp_slvs.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse slvs file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # Analyze entities (11000 = line segment)
    user_lines = [e for e in entities.values() 
                  if e.get('Entity.type') == '11000' and e.get('Entity.construction') in (None, '0')]
    
    unique_points = set()
    for l in user_lines:
        unique_points.add(l.get('Entity.point[0].v'))
        unique_points.add(l.get('Entity.point[1].v'))
        
    line_count = len(user_lines)
    node_count = len(unique_points)
    
    logger.info(f"Parsed topology: {line_count} lines, {node_count} nodes")

    # Topological Check
    if line_count == 11 and node_count == 7:
        score += 30
        feedback_parts.append("Perfect topology (11 lines, 7 nodes)")
    elif line_count >= 9 and node_count >= 6:
        score += 10
        feedback_parts.append(f"Partial topology ({line_count} lines, {node_count} nodes)")
    else:
        feedback_parts.append(f"Incorrect topology ({line_count} lines, {node_count} nodes; expected 11, 7)")

    # Analyze constraints
    c_types = [c.get('Constraint.type') for c in constraints]
    has_horizontal = '80' in c_types
    has_equal_length = '50' in c_types
    has_distance = '30' in c_types or '31' in c_types

    if has_horizontal and has_equal_length and has_distance:
        score += 10
        feedback_parts.append("Correct constraints applied")
    else:
        feedback_parts.append("Missing required constraints (Horizontal, Equal Length, or Distance)")

    # Solver Mathematical Check (Equal segments of 50mm)
    all_lengths_correct = True
    measured_lengths = []
    
    for l in user_lines:
        p1_id = l.get('Entity.point[0].v')
        p2_id = l.get('Entity.point[1].v')
        p1 = entities.get(p1_id)
        p2 = entities.get(p2_id)
        
        if p1 and p2 and 'Entity.actPoint.x' in p1 and 'Entity.actPoint.y' in p1:
            try:
                x1, y1 = float(p1['Entity.actPoint.x']), float(p1['Entity.actPoint.y'])
                x2, y2 = float(p2['Entity.actPoint.x']), float(p2['Entity.actPoint.y'])
                dist = math.sqrt((x2-x1)**2 + (y2-y1)**2)
                measured_lengths.append(dist)
            except ValueError:
                pass

    if len(measured_lengths) > 0:
        # Check if they are all ~50mm
        if all(49.0 <= d <= 51.0 for d in measured_lengths) and len(measured_lengths) == line_count:
            score += 20
            feedback_parts.append("Solver successfully perfectly resolved all lengths to ~50mm")
        elif all(abs(d - measured_lengths[0]) < 1.0 for d in measured_lengths):
            score += 10
            feedback_parts.append("Lines are equal length, but not 50mm")
        else:
            feedback_parts.append("Lines are not mathematically equal length")

    # Y-Alignment (Chord levelness) Check
    y_coords = []
    for pid in unique_points:
        p = entities.get(pid)
        if p and 'Entity.actPoint.y' in p:
            try:
                y_coords.append(float(p['Entity.actPoint.y']))
            except ValueError:
                pass
                
    if y_coords:
        # Cluster Y coordinates
        y_coords.sort()
        clusters = []
        for y in y_coords:
            if not clusters:
                clusters.append([y])
            else:
                if abs(y - clusters[-1][-1]) < 2.0:
                    clusters[-1].append(y)
                else:
                    clusters.append([y])
        
        if len(clusters) == 2:
            score += 10
            feedback_parts.append("Perfect horizontal alignment (exactly 2 chord levels detected)")
        else:
            feedback_parts.append(f"Imperfect chord alignment (detected {len(clusters)} distinct Y-levels, expected 2)")

    # 3. VLM Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            
            if final_frame:
                vlm_res = query_vlm(
                    images=frames + [final_frame],
                    prompt=VERIFICATION_PROMPT
                )
                
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('shows_warren_truss') and parsed.get('is_connected_wireframe'):
                        score += 20
                        feedback_parts.append("VLM confirmed visual truss appearance")
                    else:
                        feedback_parts.append(f"VLM did not confirm truss: {parsed.get('reasoning', 'Unknown')}")
                else:
                    feedback_parts.append("VLM evaluation failed")
            else:
                feedback_parts.append("No final screenshot available for VLM")
    except ImportError:
        logger.warning("VLM module not available, skipping visual check")

    # Threshold for pass
    passed = score >= 70 and line_count >= 9
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }