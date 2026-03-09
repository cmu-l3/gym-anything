#!/usr/bin/env python3
"""
Verifier for t_intersection_plan task.

Scoring breakdown:
1. File Mechanics (10 pts): File exists, is valid DXF, created during task.
2. Layer Structure (15 pts): All required layers exist.
3. Geometry Content (30 pts):
   - Road edges present (10 pts)
   - Center lines present (5 pts)
   - Curb return arcs with correct radius (15 pts)
4. Annotation Content (15 pts): Text labels and dimensions present.
5. VLM Verification (30 pts): Visual confirmation of T-intersection shape and layout.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_t_intersection_plan(traj, env_info, task_info):
    """
    Verify the T-intersection drawing task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    dxf_data = result.get("dxf_analysis", {})
    valid_dxf = dxf_data.get("valid_dxf", False)
    
    # ---------------------------------------------------------
    # Criterion 1: File Mechanics (10 pts)
    # ---------------------------------------------------------
    if output_exists and file_created and valid_dxf:
        score += 10
        feedback_parts.append("Valid DXF file created.")
    elif output_exists and valid_dxf:
        score += 5
        feedback_parts.append("DXF file exists but timestamp check unclear.")
    else:
        feedback_parts.append("No valid DXF file created.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ---------------------------------------------------------
    # Criterion 2: Layer Structure (15 pts)
    # ---------------------------------------------------------
    layers = set(dxf_data.get("layers", []))
    required_layers = {"ROAD_EDGE", "CURB_RETURN", "CENTER_LINE", "ANNOTATIONS"}
    missing_layers = required_layers - layers
    
    if not missing_layers:
        score += 15
        feedback_parts.append("All layers present.")
    else:
        partial = max(0, 15 - (len(missing_layers) * 4))
        score += partial
        feedback_parts.append(f"Missing layers: {', '.join(missing_layers)}.")

    # ---------------------------------------------------------
    # Criterion 3: Geometry Content (30 pts)
    # ---------------------------------------------------------
    counts = dxf_data.get("entity_counts", {})
    
    # Road Edges (10 pts) - Look for lines on ROAD_EDGE
    road_lines = counts.get("ROAD_EDGE:LINE", 0) + counts.get("ROAD_EDGE:LWPOLYLINE", 0)
    if road_lines >= 4:
        score += 10
        feedback_parts.append("Road edges detected.")
    elif road_lines > 0:
        score += 5
        feedback_parts.append("Incomplete road edges.")
    else:
        feedback_parts.append("No road edges found on ROAD_EDGE layer.")

    # Center Lines (5 pts)
    center_lines = counts.get("CENTER_LINE:LINE", 0) + counts.get("CENTER_LINE:LWPOLYLINE", 0)
    if center_lines >= 2:
        score += 5
        feedback_parts.append("Center lines detected.")
    else:
        feedback_parts.append("Missing center lines.")

    # Curb Returns (15 pts) - Check radius
    curb_arcs = dxf_data.get("curb_arcs", [])
    correct_radius_arcs = [a for a in curb_arcs if 7.5 <= a.get("radius", 0) <= 8.5]
    
    if len(correct_radius_arcs) >= 2:
        score += 15
        feedback_parts.append("Correct curb return arcs detected.")
    elif len(correct_radius_arcs) == 1:
        score += 7
        feedback_parts.append("Only one correct curb return arc found.")
    elif len(curb_arcs) >= 2:
        score += 5
        feedback_parts.append("Curb arcs present but incorrect radius.")
    else:
        feedback_parts.append("Missing curb return arcs.")

    # ---------------------------------------------------------
    # Criterion 4: Annotation Content (15 pts)
    # ---------------------------------------------------------
    text_content = [t.upper() for t in dxf_data.get("text_content", [])]
    has_main = any("MAIN" in t for t in text_content)
    has_branch = any("BRANCH" in t for t in text_content)
    
    if has_main and has_branch:
        score += 10
        feedback_parts.append("Text labels correct.")
    elif has_main or has_branch:
        score += 5
        feedback_parts.append("One text label missing.")
    
    dim_count = dxf_data.get("dimensions_count", 0)
    if dim_count >= 2:
        score += 5
        feedback_parts.append("Dimensions detected.")
    else:
        feedback_parts.append("Missing dimensions.")

    # ---------------------------------------------------------
    # Criterion 5: VLM Verification (30 pts)
    # ---------------------------------------------------------
    # Sample trajectory to see if they actually drew it or just scripted it/pasted it
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are evaluating a CAD drafting task. 
    Goal: Draw a T-intersection road layout.
    
    Look at the screenshots.
    1. Do you see a T-shaped intersection being drawn?
    2. Are there curved corners (arcs) where the roads meet?
    3. Is there text visible (e.g., "MAIN ROAD", "BRANCH ROAD")?
    4. Are there dimension lines visible?
    
    Answer JSON: {"t_shape_visible": bool, "arcs_visible": bool, "text_visible": bool, "dimensions_visible": bool}
    """
    
    vlm_score = 0
    try:
        vlm_result = query_vlm(images=frames + [final_screen], prompt=vlm_prompt).get("parsed", {})
        
        if vlm_result.get("t_shape_visible"): vlm_score += 10
        if vlm_result.get("arcs_visible"): vlm_score += 10
        if vlm_result.get("text_visible"): vlm_score += 5
        if vlm_result.get("dimensions_visible"): vlm_score += 5
        
        score += vlm_score
        feedback_parts.append(f"VLM verification score: {vlm_score}/30")
        
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Fallback: if programmatic check was strong, give partial VLM points
        if score >= 60:
            score += 15
            feedback_parts.append("VLM skipped (error), awarded partial fallback points.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }