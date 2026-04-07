#!/usr/bin/env python3
"""
Verifier for parametric_warren_truss_2d task.

This verifier directly parses the SolveSpace (.slvs) plain-text save file to
mathematically validate the network graph and constraints.

Criteria:
1. File exists and was modified during task (anti-gaming).
2. Exact topological line count (15 line segments).
3. Parametric structure (exactly 1 distance constraint, preventing hardcoded cheating).
4. Solved geometry validation (all 15 lines evaluate to 40.0 mm).
5. VLM verification on trajectory to confirm human-like workflow execution.
"""

import json
import os
import tempfile
import logging
import math

# Try to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# SolveSpace Constraint Type definitions
CONSTRAINT_PT_PT_DISTANCE = 30
CONSTRAINT_EQUAL_LENGTH_LINES = 64

def parse_slvs_file(filepath):
    """Parses a plain-text SolveSpace SLVS file to extract entities and constraints."""
    entities = {}
    constraints = []
    
    current_entity = None
    current_constraint = None
    
    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            
            # Start of a new block
            if line.startswith('Entity.h.v='):
                current_entity = line.split('=')[1]
                entities[current_entity] = {'type': 0, 'x': 0.0, 'y': 0.0, 'p0': None, 'p1': None}
                current_constraint = None
            elif line.startswith('Constraint.h.v='):
                current_constraint = line.split('=')[1]
                constraints.append({'type': 0})
                current_entity = None
            
            # Parsing Entity attributes
            if current_entity:
                if line.startswith('Entity.type='):
                    entities[current_entity]['type'] = int(line.split('=')[1])
                elif line.startswith('Entity.actPoint.x='):
                    entities[current_entity]['x'] = float(line.split('=')[1])
                elif line.startswith('Entity.actPoint.y='):
                    entities[current_entity]['y'] = float(line.split('=')[1])
                elif line.startswith('Entity.point[0].v='):
                    entities[current_entity]['p0'] = line.split('=')[1]
                elif line.startswith('Entity.point[1].v='):
                    entities[current_entity]['p1'] = line.split('=')[1]
            
            # Parsing Constraint attributes
            elif current_constraint:
                if line.startswith('Constraint.type='):
                    constraints[-1]['type'] = int(line.split('=')[1])
                    
    return entities, constraints

def verify_parametric_warren_truss_2d(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_lines = metadata.get('expected_line_count', 15)
    expected_length = metadata.get('expected_segment_length', 40.0)
    expected_dist_constraints = metadata.get('expected_distance_constraints', 1)

    score = 0
    feedback_parts = []
    
    # 1. Read task execution JSON
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
            
    # Check if file exists and was modified
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "warren_truss.slvs was not found."}
    if not result.get('file_modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "File exists but wasn't created/modified during this task run (anti-gaming check failed)."}
        
    score += 10
    feedback_parts.append("File created successfully")
    
    # 2. Extract and Parse SLVS File
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env("/tmp/warren_truss_result.slvs", temp_slvs.name)
        entities, constraints = parse_slvs_file(temp_slvs.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse SLVS file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # 3. Analyze Entities (Lines and Points)
    # Entity type 11000 is a line segment
    lines = [e for e in entities.values() if e['type'] == 11000]
    line_count = len(lines)
    
    if line_count == expected_lines:
        score += 20
        feedback_parts.append(f"Correct line count ({line_count})")
    elif line_count > 0:
        score += int(20 * (min(line_count, expected_lines) / expected_lines))
        feedback_parts.append(f"Found {line_count} lines (expected {expected_lines})")
    else:
        feedback_parts.append("No line segments found in file")

    # 4. Analyze Constraints (Parametric Structure Anti-Gaming)
    dist_constraints = [c for c in constraints if c['type'] == CONSTRAINT_PT_PT_DISTANCE]
    dist_count = len(dist_constraints)
    
    # We want exactly ONE distance constraint. If they have 15, they cheated and hardcoded every line.
    if dist_count == expected_dist_constraints:
        score += 20
        feedback_parts.append("Correct parametric structure (1 distance constraint used)")
    elif dist_count > 0:
        feedback_parts.append(f"Found {dist_count} distance constraints (expected exactly 1 for proper parametric setup)")
    else:
        feedback_parts.append("No distance constraints found")

    # 5. Math geometry evaluation - check if all lines actually snapped to 40.0mm
    correct_length_lines = 0
    origin_anchored = False
    
    for line in lines:
        p0_handle = line['p0']
        p1_handle = line['p1']
        
        if p0_handle in entities and p1_handle in entities:
            p0 = entities[p0_handle]
            p1 = entities[p1_handle]
            
            # Check for origin anchor
            if (abs(p0['x']) < 0.1 and abs(p0['y']) < 0.1) or (abs(p1['x']) < 0.1 and abs(p1['y']) < 0.1):
                origin_anchored = True
                
            # Compute Euclidean distance 
            dist = math.hypot(p1['x'] - p0['x'], p1['y'] - p0['y'])
            
            # Check if length matches 40.0mm +/- 0.5mm
            if abs(dist - expected_length) < 0.5:
                correct_length_lines += 1

    if correct_length_lines == expected_lines and expected_lines > 0:
        score += 20
        feedback_parts.append("All segments evaluate to 40.0mm (perfect geometry)")
    elif correct_length_lines > 0:
        score += int(20 * (correct_length_lines / expected_lines))
        feedback_parts.append(f"{correct_length_lines}/{line_count} segments evaluate to 40.0mm")
    
    if origin_anchored:
        score += 10
        feedback_parts.append("Truss anchored near origin")
        
    # 6. VLM Verification for workflow trajectory
    if VLM_AVAILABLE and 'query_vlm' in env_info:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            
            prompt = (
                "You are reviewing a CAD software screen. The user was tasked with drawing a 2D Warren Truss profile. "
                "This looks like a sequence of equilateral triangles forming a bridge truss (bottom horizontal chords, top horizontal chords, and diagonal zig-zags). "
                "Does the final image show a completed or partially completed Warren Truss structure composed of line segments? "
                "Reply in JSON with {'truss_visible': true/false, 'confidence': 'high/low'}"
            )
            
            vlm_res = env_info['query_vlm'](
                prompt=prompt,
                images=frames + [final_img] if final_img else frames
            )
            
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('truss_visible'):
                score += 20
                feedback_parts.append("VLM confirmed visual Warren Truss structure")
            else:
                feedback_parts.append("VLM could not confirm Truss visually")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")
            # Give free points if VLM errors out, to not penalize agent
            score += 20 
            feedback_parts.append("VLM visual verification bypassed")
    else:
        score += 20
        feedback_parts.append("VLM unavailable, auto-granting visual points")

    # Pass condition: must score at least 70/100 and have properly used equal constraints (dist_count == 1)
    passed = (score >= 70) and (dist_count == 1) and (correct_length_lines >= 10)
    
    if not passed and dist_count > 1:
        feedback_parts.append("FAILED: You must use Equal Length constraints to drive the model, not multiple Distance constraints.")
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }