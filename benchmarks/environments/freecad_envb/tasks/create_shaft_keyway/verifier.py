#!/usr/bin/env python3
"""
Verifier for create_shaft_keyway task.

Checks:
1. File existence and valid FreeCAD format.
2. Anti-gaming (file created during task).
3. Geometric accuracy (Dimensions, Volume, Keyway subtraction).
4. VLM visual confirmation.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_shaft_keyway(traj, env_info, task_info):
    """
    Verify the drive shaft with keyway creation.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    expected_length = metadata.get('shaft_length', 80.0)
    expected_diameter = metadata.get('shaft_diameter', 12.0)
    # Full cylinder volume ~9047 mm3. Keyway removes ~4*2.5*30 = 300 mm3. Expected ~8747.
    expected_vol_min = metadata.get('expected_volume_range', [8200, 9000])[0]
    expected_vol_max = metadata.get('expected_volume_range', [8200, 9000])[1]

    score = 0
    feedback_parts = []
    
    # Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Basic File Checks (20 pts)
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    score += 10
    feedback_parts.append("File exists")

    if result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (anti-gaming fail)")

    # 3. Geometric Analysis (60 pts)
    geom = result.get('geometry', {})
    
    if not geom.get('valid_fcstd'):
        feedback_parts.append("File is not a valid FreeCAD document")
    elif not geom.get('has_solid'):
        feedback_parts.append("Document contains no solid shape")
    else:
        bbox = geom.get('bbox', [0, 0, 0]) # Sorted [min, mid, max]
        volume = geom.get('volume', 0)
        
        # Check Length (Target 80mm)
        if abs(bbox[2] - expected_length) < 3.0:
            score += 20
            feedback_parts.append(f"Length correct ({bbox[2]:.1f}mm)")
        else:
            feedback_parts.append(f"Length incorrect ({bbox[2]:.1f}mm vs {expected_length}mm)")

        # Check Diameter (Target 12mm for other two dims)
        if abs(bbox[0] - expected_diameter) < 2.0 and abs(bbox[1] - expected_diameter) < 2.0:
            score += 20
            feedback_parts.append(f"Diameter correct ({bbox[0]:.1f}mm)")
        else:
            feedback_parts.append(f"Diameter incorrect ({bbox[0]:.1f}x{bbox[1]:.1f}mm vs {expected_diameter}mm)")

        # Check Volume (Did they cut the keyway?)
        # Full cylinder is ~9048. If volume is too close to that, they didn't cut.
        # If volume is in range [8200, 9000], it likely has the cut.
        if expected_vol_min <= volume <= expected_vol_max:
            score += 20
            feedback_parts.append(f"Volume correct (Keyway cut detected, {volume:.0f}mm³)")
        elif volume > 9000:
            score += 5 # Partial credit for full cylinder
            feedback_parts.append(f"Volume too high - keyway likely missing ({volume:.0f}mm³)")
        else:
            feedback_parts.append(f"Volume incorrect ({volume:.0f}mm³)")

    # 4. VLM Verification (20 pts)
    # Use trajectory to see if they were doing CAD work
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        if final_img:
            frames.append(final_img)
            
        prompt = """
        Review these screenshots of a FreeCAD user session.
        The user is supposed to create a cylindrical shaft with a rectangular keyway slot cut into it.
        
        1. Do you see a 3D cylindrical shape?
        2. Do you see a rectangular slot/cutout on the side of the cylinder (a keyway)?
        3. Does the final state look like a completed mechanical part?
        
        Return JSON: {"cylinder_visible": bool, "keyway_visible": bool, "looks_complete": bool}
        """
        
        vlm_out = query_vlm(images=frames, prompt=prompt)
        parsed = vlm_out.get('parsed', {})
        
        if parsed.get('cylinder_visible'):
            vlm_score += 5
        if parsed.get('keyway_visible'):
            vlm_score += 10
        if parsed.get('looks_complete'):
            vlm_score += 5
            
        score += vlm_score
        if vlm_score > 0:
            feedback_parts.append(f"Visual verification: {vlm_score}/20")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Be lenient if VLM fails but geometry is perfect
        if score >= 70: 
            score += 20
            feedback_parts.append("VLM skipped (Geometry passed)")

    # Final scoring
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }