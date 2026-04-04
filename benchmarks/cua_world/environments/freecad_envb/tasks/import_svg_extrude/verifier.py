#!/usr/bin/env python3
"""
Verifier for import_svg_extrude task.

Verifies:
1. File creation/modification validity (Anti-gaming)
2. Geometric properties (Bounding Box, Volume, Solid type)
3. VLM Trajectory check (Visual confirmation of workflow)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_svg_extrude(traj, env_info, task_info):
    """
    Verify the FreeCAD Import/Extrude task.
    """
    # 1. Setup and file retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Get metadata specs
    specs = task_info.get('metadata', {}).get('geometry_specs', {})
    expected_x = specs.get('bbox_x', 60.0)
    expected_y = specs.get('bbox_y', 30.0)
    expected_z = specs.get('bbox_z', 3.0)
    tolerance = specs.get('tolerance_mm', 1.0)
    max_vol = specs.get('max_solid_volume_mm3', 5400) # 60*30*3
    min_vol = specs.get('min_solid_volume_mm3', 3500) # accounting for holes

    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Basic File Checks (20 points)
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file sensor_mount.FCStd not found."}
    
    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp predates task start (Anti-gaming failure)."}

    score += 10 # File exists
    
    geo = result.get('geometry', {})
    if geo.get('valid_doc'):
        score += 10 # Valid FreeCAD doc
        feedback_parts.append("Valid FreeCAD document created.")
    else:
        feedback_parts.append("File is not a valid FreeCAD document.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 3. Geometric Verification (50 points)
    # Check if a 3D solid exists
    if geo.get('has_solid'):
        score += 10
        feedback_parts.append("3D Solid found.")
    else:
        feedback_parts.append("No 3D solid found (wireframe or face only).")
    
    # Check Bounding Box
    bx = geo.get('bbox_x', 0)
    by = geo.get('bbox_y', 0)
    bz = geo.get('bbox_z', 0)
    
    bbox_ok = (abs(bx - expected_x) <= tolerance and 
               abs(by - expected_y) <= tolerance and 
               abs(bz - expected_z) <= tolerance)
    
    if bbox_ok:
        score += 20
        feedback_parts.append(f"Dimensions correct ({bx:.1f}x{by:.1f}x{bz:.1f}mm).")
    else:
        feedback_parts.append(f"Incorrect dimensions: {bx:.1f}x{by:.1f}x{bz:.1f}mm (Expected ~{expected_x}x{expected_y}x{expected_z}).")

    # Check Volume (verifies holes are cut)
    vol = geo.get('volume', 0)
    # Volume should be LESS than full block (5400) but MORE than empty (0)
    # Ideally around 4000-4500 depending on exact hole calculation
    if min_vol <= vol < max_vol:
        score += 20
        feedback_parts.append(f"Volume correct ({vol:.1f} mm³), indicating holes are present.")
    elif vol >= max_vol:
        feedback_parts.append(f"Volume too high ({vol:.1f} mm³). Did you cut the holes?")
        # Partial credit if dimensions are right but holes missing
    else:
        feedback_parts.append(f"Volume too low or zero ({vol:.1f} mm³).")

    # 4. VLM Verification (30 points)
    # Use VLM to confirm the visual appearance and workflow
    vlm_score = 0
    vlm_feedback = ""
    
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        prompt = """
        Review this sequence of FreeCAD screenshots.
        The user task is: Import an SVG, Extrude it to a plate, and Cut holes.
        
        1. Do you see an imported 2D outline (black lines/paths)?
        2. Do you see a 3D gray/shaded solid being created?
        3. In the final result, does the object look like a flat plate with holes in it?
        
        Return JSON:
        {
            "imported_svg_visible": true/false,
            "extrusion_performed": true/false,
            "final_object_has_holes": true/false,
            "score_confidence": 0-10
        }
        """
        
        vlm_res = query_vlm(images=frames + [final_img], prompt=prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('imported_svg_visible'): vlm_score += 10
        if parsed.get('extrusion_performed'): vlm_score += 10
        if parsed.get('final_object_has_holes'): vlm_score += 10
        
        feedback_parts.append(f"VLM Analysis: {parsed}")
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # If VLM fails, we rely on geometry score, but max score is capped
        vlm_feedback = "VLM check skipped."

    score += vlm_score

    # Final Pass Determination
    # Must have correct bbox and solid to pass
    passed = (score >= 60 and bbox_ok and geo.get('has_solid'))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }