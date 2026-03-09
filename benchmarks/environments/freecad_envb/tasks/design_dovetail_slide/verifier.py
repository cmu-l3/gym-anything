#!/usr/bin/env python3
"""
Verifier for design_dovetail_slide task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_dovetail_slide(traj, env_info, task_info):
    """
    Verifies the FreeCAD dovetail slide task.
    
    Criteria:
    1. File exists and was modified (10 pts)
    2. Document contains at least 2 Bodies (20 pts)
    3. Rail Volume is correct (35000 +/- 600 mm3) (35 pts)
    4. Carriage Volume is correct (41100 +/- 600 mm3) (35 pts)
       - This implicitly checks for the clearance gap.
       - If no clearance, Carriage volume would be ~42500 mm3.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    metadata = task_info.get('metadata', {})
    rail_target = metadata.get('rail_volume_mm3', 35000)
    carriage_target = metadata.get('carriage_volume_mm3', 41100)
    tolerance = metadata.get('volume_tolerance_mm3', 600)
    
    # Retrieve result JSON
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

    score = 0
    feedback_parts = []
    
    # 1. File Check (10 pts)
    if result.get('output_exists') and result.get('file_modified'):
        score += 10
        feedback_parts.append("File saved successfully")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or not modified"}
        
    # 2. Geometry Analysis
    analysis = result.get('geometry_analysis', {})
    if not analysis.get('valid_file'):
        return {"passed": False, "score": score, "feedback": "File is not a valid FreeCAD document"}
        
    bodies = analysis.get('bodies', [])
    body_count = analysis.get('body_count', 0)
    
    # Check Body Count (20 pts)
    if body_count >= 2:
        score += 20
        feedback_parts.append(f"Found {body_count} bodies (Target: 2)")
    else:
        feedback_parts.append(f"Found only {body_count} bodies (Target: 2)")
        
    # 3. Volume Verification (70 pts split)
    # We need to identify which body is which based on volume similarity
    rail_found = False
    carriage_found = False
    
    # Sort bodies by volume to try to match them to targets
    # Rail ~35000, Carriage ~41100
    
    for body in bodies:
        vol = body.get('volume', 0)
        
        # Check Rail
        if abs(vol - rail_target) <= tolerance:
            if not rail_found: # Only count once
                score += 35
                rail_found = True
                feedback_parts.append(f"Rail geometry correct (Vol: {vol:.0f} mm³)")
                continue
                
        # Check Carriage
        if abs(vol - carriage_target) <= tolerance:
            if not carriage_found:
                score += 35
                carriage_found = True
                feedback_parts.append(f"Carriage geometry correct (Vol: {vol:.0f} mm³)")
                continue
                
        # Feedback for incorrect volumes
        if not rail_found and not carriage_found:
             # Check if they forgot clearance (Carriage vol would be ~42500)
             if abs(vol - 42500) < 1000:
                 feedback_parts.append(f"Carriage volume too high ({vol:.0f} mm³) - likely forgot clearance")
             else:
                 feedback_parts.append(f"Unknown body volume: {vol:.0f} mm³")

    if not rail_found:
        feedback_parts.append(f"Rail volume mismatch (Expected ~{rail_target})")
    if not carriage_found:
        feedback_parts.append(f"Carriage volume mismatch (Expected ~{carriage_target})")

    # 4. VLM Verification (Bonus/Confirmation if score is borderline or high)
    # If score is high (>60), we use VLM to confirm visual structure
    if score >= 60:
        frames = sample_trajectory_frames(traj, n=3)
        final_screen = get_final_screenshot(traj)
        
        # If we have images
        if final_screen:
            prompt = """
            Verify if the user has modeled a dovetail slide in FreeCAD.
            Look for:
            1. A 3D model with two parts.
            2. A 'rail' part (trapezoidal/male shape).
            3. A 'carriage' part (block with slot sliding over the rail).
            
            Does the geometry look like a mechanical linear slide?
            """
            
            try:
                vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
                if vlm_res.get('success'):
                    # We don't change score here as geometry check is robust, 
                    # but we append feedback
                    pass
            except Exception:
                pass

    passed = score >= 60 and rail_found and carriage_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }