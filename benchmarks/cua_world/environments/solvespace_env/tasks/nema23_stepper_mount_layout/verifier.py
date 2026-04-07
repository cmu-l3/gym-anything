#!/usr/bin/env python3
"""
Verifier for nema23_stepper_mount_layout task.

Verifies:
1. File exists and was created during the task run (timestamp check).
2. The SLVS file contains construction lines (square outline).
3. The SLVS file contains standard solid circles (mounting holes & bore).
4. Distance/diameter constraints match the NEMA 23 standard dimensions.
5. VLM evaluation confirms the visual layout (dashed square, solid circles, centered).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_slvs(filepath):
    """
    Parses a SolveSpace SLVS file.
    SLVS files are plaintext blocks of keys and values separated by blank lines.
    Returns a list of dictionaries representing each block.
    """
    blocks = []
    current_block = {}
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line:
                if current_block:
                    blocks.append(current_block)
                    current_block = {}
            elif '=' in line:
                parts = line.split('=', 1)
                if len(parts) == 2:
                    current_block[parts[0]] = parts[1]
        if current_block:
            blocks.append(current_block)
    return blocks


def has_constraint_value(val_list, expected, tol=0.1):
    """Checks if a float constraint value is present within a given tolerance."""
    for v in val_list:
        try:
            vf = float(v)
            if abs(vf - expected) <= tol:
                return True
        except ValueError:
            pass
    return False


def verify_nema23_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Read task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    
    if not output_exists or not created_during_task:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file was not saved or was not modified during the task."
        }
        
    # 2. Parse SLVS file
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        copy_from_env("/tmp/nema23_layout.slvs", temp_slvs.name)
        blocks = parse_slvs(temp_slvs.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy and parse SLVS file: {e}"}
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)
            
    score = 20 # 20 points for correctly creating/saving the file during the session
    feedback_parts = ["File created successfully"]
    
    # Analyze SLVS geometry
    # In SolveSpace, Line entity types are usually 11000/11001. Circles are 2000-2004.
    # Constraints are type 30, 31, 32, 33 for distance/diameter/radius.
    lines = [b for b in blocks if b.get('Entity.type') in ('11000', '11001')]
    circles = [b for b in blocks if b.get('Entity.type') in ('2000', '2001', '2002', '2003', '2004')]
    constraints = [b for b in blocks if b.get('Constraint.type') in ('30', '31', '32', '33')]
    
    construction_lines = [l for l in lines if l.get('Entity.construction') == '1']
    solid_circles = [c for c in circles if c.get('Entity.construction', '0') == '0']
    
    # Criterion A: Construction Lines (15 pts)
    if len(construction_lines) >= 4:
        score += 15
        feedback_parts.append("Construction geometry applied")
    else:
        feedback_parts.append(f"Missing construction lines (found {len(construction_lines)})")
        
    # Criterion B: Solid Circles (15 pts)
    if len(solid_circles) >= 5:
        score += 15
        feedback_parts.append("All solid circles drawn")
    else:
        feedback_parts.append(f"Missing solid circles (found {len(solid_circles)})")
        
    # Criterion C: NEMA 23 Constraints (20 pts)
    c_vals = [c.get('Constraint.valA') for c in constraints if c.get('Constraint.valA')]
    has_47 = has_constraint_value(c_vals, 47.14)
    has_38 = has_constraint_value(c_vals, 38.1) or has_constraint_value(c_vals, 19.05) # Diameter or Radius
    has_5 = has_constraint_value(c_vals, 5.0) or has_constraint_value(c_vals, 2.5)     # Diameter or Radius
    
    dim_score = 0
    if has_47: dim_score += 7
    if has_38: dim_score += 7
    if has_5: dim_score += 6
    
    score += dim_score
    if dim_score == 20:
        feedback_parts.append("All precise dimensions configured")
    else:
        feedback_parts.append("Some dimensions missing or incorrect")
        
    # 3. VLM Trajectory Verification (30 pts)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = (
            "You are evaluating a parametric 2D CAD design task in SolveSpace. "
            "The goal was to draw a precise NEMA 23 stepper motor mounting layout: "
            "1) A dashed line (construction geometry) square centered on the origin. "
            "2) 4 solid circles centered exactly on the corners of the dashed square. "
            "3) 1 larger solid central circle centered on the origin. "
            "Look at the trajectory and final image. Did the agent successfully create this specific visual layout? "
            "Respond ONLY in JSON format like this: {\"success\": true/false, \"reasoning\": \"...\"}."
        )
        
        try:
            vlm_resp = query_vlm(images=images, prompt=prompt)
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("success", False):
                score += 30
                feedback_parts.append("VLM visual verification passed")
            else:
                feedback_parts.append("VLM visual verification failed")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("VLM evaluation error")
    else:
        feedback_parts.append("VLM query function not available")
            
    # Set passed threshold to 75%
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }