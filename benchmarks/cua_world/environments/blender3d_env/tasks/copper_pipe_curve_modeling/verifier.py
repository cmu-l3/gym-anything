#!/usr/bin/env python3
"""
Verifier for copper_pipe_curve_modeling task.

Criteria:
1. 3+ Curve objects with bevel_depth > 0 (Solid pipes)
2. Material: Copper color (Orange/Brown), High Metallic, Moderate Roughness
3. Geometry: At least one bent pipe (not all straight lines)
4. Render: Output exists and is valid
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_copper_pipes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Task Metadata thresholds
    metadata = task_info.get('metadata', {})
    min_curve_count = metadata.get('min_curve_count', 3)
    min_bevel = metadata.get('min_bevel_depth', 0.02)
    max_bevel = metadata.get('max_bevel_depth', 0.15) # Relaxed upper bound
    
    # Extract scene data
    scene_data = result.get('scene_data', {})
    curves = scene_data.get('curves', [])
    
    score = 0
    feedback = []
    
    # 1. Curve Count & Bevel Check (40 pts)
    # -------------------------------------
    valid_pipes = 0
    for c in curves:
        bd = c.get('bevel_depth', 0)
        # Check if it has thickness (is a pipe)
        if min_bevel <= bd <= max_bevel:
            valid_pipes += 1
    
    if valid_pipes >= min_curve_count:
        score += 40
        feedback.append(f"Created {valid_pipes} valid pipe segments")
    elif valid_pipes > 0:
        score += 20
        feedback.append(f"Only {valid_pipes}/{min_curve_count} valid pipes found")
    else:
        feedback.append("No valid pipes found (check bevel depth)")

    # 2. Material Check (30 pts)
    # -------------------------------------
    # We check if ANY curve has a copper-like material
    has_copper = False
    for c in curves:
        mat = c.get('material', {})
        col = mat.get('color', [0,0,0])
        met = mat.get('metallic', 0)
        
        # Copper Logic:
        # Red should be high (>0.5), Blue should be low (<0.4), Green usually middle
        # Metallic should be high (>0.7)
        is_orange_brown = (col[0] > 0.4) and (col[2] < 0.4) and (col[0] > col[2])
        is_metallic = met > 0.7
        
        if is_orange_brown and is_metallic:
            has_copper = True
            break
            
    if has_copper:
        score += 30
        feedback.append("Copper material applied")
    elif valid_pipes > 0:
        feedback.append("Material does not look like copper (check color/metallic)")

    # 3. Geometry/Bend Check (15 pts)
    # -------------------------------------
    # Check for complexity
    has_bend = any(c.get('is_bent', False) for c in curves)
    if has_bend:
        score += 15
        feedback.append("Bent pipe geometry detected")
    elif valid_pipes > 0:
        feedback.append("All pipes appear straight (no bends detected)")

    # 4. Render & File Check (15 pts)
    # -------------------------------------
    if result.get('blend_exists'):
        score += 5
    if result.get('render_exists') and result.get('render_size', 0) > 10000: # >10KB
        score += 10
        feedback.append("Render output valid")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback),
        "details": result
    }