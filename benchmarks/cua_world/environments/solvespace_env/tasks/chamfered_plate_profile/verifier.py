#!/usr/bin/env python3
"""
Verifier for chamfered_plate_profile task.

Robust Multi-Signal Verification Strategy:
1. Programmatic evaluation of .slvs save file:
   - File was successfully created and modified during the task (anti-gaming)
   - Verifies the exact entities (8 solid lines for an octagon)
   - Verifies geometrical constraints (Horizontal, Vertical, Equal length)
   - Verifies dimension constraints matching required specifications (80, 50, 10)
2. VLM evaluation using trajectory + final frame:
   - Visually confirms the construction of the chamfered profile
   - Checks if the sketch is fully constrained in the UI (green lines)
"""

import json
import tempfile
import os
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_slvs_file(filepath):
    """Parses a raw SolveSpace .slvs file into easily analyzable blocks."""
    entities = []
    constraints = []
    
    if not os.path.exists(filepath):
        return entities, constraints
        
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
            
        current_block = {}
        for line in lines:
            line = line.strip()
            if not line:
                continue
                
            if line.startswith('Entity.'):
                k, v = line.split('=', 1)
                current_block[k] = v
            elif line == 'AddEntity':
                entities.append(current_block)
                current_block = {}
            elif line.startswith('Constraint.'):
                k, v = line.split('=', 1)
                current_block[k] = v
            elif line == 'AddConstraint':
                constraints.append(current_block)
                current_block = {}
                
        return entities, constraints
    except Exception as e:
        logger.error(f"Error parsing .slvs file: {e}")
        return [], []


def verify_chamfered_plate(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_width = metadata.get('expected_width', 80.0)
    expected_height = metadata.get('expected_height', 50.0)
    expected_chamfer = metadata.get('expected_chamfer', 10.0)

    feedback_parts = []
    score = 0
    max_score = 100

    # ================================================================
    # Read the exported JSON results
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 1. Base File Checks (15 points total)
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output .slvs file was not found. The agent did not save the design."
        }
    
    if file_created:
        score += 15
        feedback_parts.append("File newly created during task (+15)")
    else:
        feedback_parts.append("FAIL: File was not created/modified during this task session (anti-gaming)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # Parse and Validate the SLVS File (45 points total)
    # ================================================================
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    entities = []
    constraints = []
    try:
        copy_from_env("/tmp/chamfered_plate.slvs", temp_slvs.name)
        entities, constraints = parse_slvs_file(temp_slvs.name)
    except Exception as e:
        logger.error(f"Failed to copy or parse .slvs file: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    # Count Solid Line Segments (Type 11000, not construction geometry)
    # Construction entities have "Entity.construction=1"
    solid_lines = [e for e in entities if e.get('Entity.type') == '11000' and e.get('Entity.construction') != '1']
    
    if len(solid_lines) >= 8:
        score += 15
        feedback_parts.append("Has >=8 line segments (+15)")
    elif len(solid_lines) > 0:
        score += int((len(solid_lines) / 8) * 10)
        feedback_parts.append(f"Incomplete geometry: {len(solid_lines)}/8 segments")
    else:
        feedback_parts.append("No solid line segments found")

    # Analyze Constraints
    eq_len_constraints = [c for c in constraints if c.get('Constraint.type') == '50']
    horiz_constraints = [c for c in constraints if c.get('Constraint.type') == '20']
    vert_constraints = [c for c in constraints if c.get('Constraint.type') == '21']
    
    if len(eq_len_constraints) >= 3:  # 4 lines chained equal length needs min 3 constraints
        score += 10
        feedback_parts.append("Equal-length constraints applied (+10)")
    
    if len(horiz_constraints) >= 2 and len(vert_constraints) >= 2:
        score += 10
        feedback_parts.append("Horizontal/Vertical constraints applied (+10)")

    # Check Dimension Values
    dim_vals = []
    for c in constraints:
        if 'Constraint.valA' in c:
            try:
                dim_vals.append(float(c['Constraint.valA']))
            except ValueError:
                pass

    has_width = any(abs(v - expected_width) < 1.0 for v in dim_vals)
    has_height = any(abs(v - expected_height) < 1.0 for v in dim_vals)
    has_chamfer = any(abs(v - expected_chamfer) < 1.0 for v in dim_vals)
    
    dims_score = 0
    if has_width: dims_score += 3
    if has_height: dims_score += 3
    if has_chamfer: dims_score += 4
    
    score += dims_score
    if dims_score == 10:
        feedback_parts.append(f"All dimensions correct ({expected_width}, {expected_height}, {expected_chamfer}) (+10)")
    elif dims_score > 0:
        feedback_parts.append("Some dimension constraints present")
    else:
        feedback_parts.append("Missing required dimension constraints")

    # ================================================================
    # VLM Trajectory Verification (40 points total)
    # ================================================================
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    if query_vlm and len(traj) > 0:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """Analyze these screenshots of a user working in SolveSpace.
        1. Has the user drawn a closed geometric profile with 8 sides (a rectangle where all 4 corners are chamfered/cut off)?
        2. In the final screenshot, does the shape appear to be fully constrained? (In SolveSpace, unconstrained entities are red, and fully constrained entities turn green or white depending on the background).
        3. Are there dimension constraints visible matching approximately 80, 50, and 10?
        
        Return JSON exactly like this:
        {
            "has_chamfered_octagon_shape": true/false,
            "is_fully_constrained": true/false,
            "dimensions_visible": true/false,
            "reasoning": "brief explanation"
        }
        """
        
        vlm_result = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("has_chamfered_octagon_shape"):
                score += 20
                feedback_parts.append("VLM verified chamfered octagonal profile (+20)")
            else:
                feedback_parts.append("VLM did not detect correct shape")
                
            if parsed.get("is_fully_constrained"):
                score += 15
                feedback_parts.append("VLM verified sketch is fully constrained (+15)")
                
            if parsed.get("dimensions_visible"):
                score += 5
                feedback_parts.append("VLM verified dimensions are visible (+5)")
    else:
        feedback_parts.append("VLM verification skipped/unavailable")

    # Assess overall pass criteria
    passed = score >= 60 and file_created and len(solid_lines) >= 6

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }