#!/usr/bin/env python3
"""
Verifier for design_pcb_housing task.

Verifies:
1. File existence and validity.
2. Geometric properties (Bounding Box, Volume) via programmatic analysis inside container.
3. Feature presence (Standoffs, Cutouts) via volume and face counts.
4. Visual verification via VLM (final confirmation of shape).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_pcb_housing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_vol = metadata.get('target_volume_mm3', 29612.0)
    vol_tol = metadata.get('volume_tolerance_percent', 5.0)
    
    # Load result file
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

    score = 0
    feedback_parts = []
    
    # 1. File Check (10 pts)
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "No output file found"}
        
    score += 10
    feedback_parts.append("File created")

    # 2. Geometric Analysis (Programmatic)
    geo = result.get('geometry_analysis', {})
    
    # Bounding Box Check (20 pts)
    # Expected: 100 x 60 x 30
    bbox = geo.get('bbox', [0, 0, 0])
    # Sort dims to allow for rotation (though prompt specified orientation, we can be slightly lenient on axis if dimensions match)
    dims = sorted(bbox)
    expected_dims = sorted([100.0, 60.0, 30.0])
    
    dims_match = True
    for d, e in zip(dims, expected_dims):
        if abs(d - e) > 1.0: # 1mm tolerance
            dims_match = False
            
    if dims_match:
        score += 20
        feedback_parts.append("Bounding box correct")
    else:
        feedback_parts.append(f"Dimensions incorrect: {bbox}")

    # Volume Check (30 pts)
    # This acts as a proxy for wall thickness and feature existence
    vol = geo.get('volume', 0)
    vol_err_pct = abs(vol - target_vol) / target_vol * 100
    
    if vol_err_pct <= vol_tol:
        score += 30
        feedback_parts.append(f"Volume accurate ({vol:.0f} mm3)")
    elif vol_err_pct <= vol_tol * 2:
        score += 15
        feedback_parts.append(f"Volume slightly off ({vol:.0f} mm3)")
    else:
        feedback_parts.append(f"Volume mismatch ({vol:.0f} vs {target_vol:.0f})")

    # Feature Check: Cylindrical Faces (Standoffs) (10 pts)
    # 4 standoffs = 4 outer cylinders + 4 inner holes = 8 cylindrical faces minimum
    cyl_faces = geo.get('cylindrical_faces', 0)
    if cyl_faces >= 8:
        score += 10
        feedback_parts.append("Standoffs detected (geometry)")
    elif cyl_faces >= 4:
        score += 5
        feedback_parts.append("Partial standoffs detected")

    # 3. VLM Verification (30 pts)
    # To confirm the cutout and general shape "look" right
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        Analyze this FreeCAD screenshot of a PCB housing box.
        1. Is there a rectangular box visible?
        2. Are there 4 internal posts/standoffs on the floor?
        3. Is there a square/rectangular cutout on one of the side walls (for a USB port)?
        4. Does the box look open at the top?
        
        Return JSON: {"box_visible": bool, "standoffs_visible": bool, "cutout_visible": bool, "open_top": bool}
        """
        vlm_res = query_vlm(prompt, image=final_screenshot)
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('box_visible'): vlm_score += 5
            if parsed.get('open_top'): vlm_score += 5
            if parsed.get('standoffs_visible'): vlm_score += 10
            if parsed.get('cutout_visible'): vlm_score += 10
            
            feedback_parts.append("Visual verification completed")
        else:
            feedback_parts.append("Visual verification failed")
    
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }