#!/usr/bin/env python3
"""
Verifier for create_revolution task.

Verifies:
1. File existence and valid timestamp (Anti-gaming).
2. Geometry correctness via internal FreeCAD inspection (Volume, BBox).
3. Process verification via VLM (Trajectory).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_revolution(traj, env_info, task_info):
    """
    Verify that the stepped shaft was created correctly.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vol = metadata.get('expected_volume_mm3', 24702.0)
    vol_tol = expected_vol * (metadata.get('volume_tolerance_percent', 15) / 100.0)
    
    # Expected BBox: ~30x30x60 mm (Sorted dimensions)
    # The shaft is 60mm tall, and max diameter is 30mm.
    expected_bbox = [30.0, 30.0, 60.0] 
    bbox_tol = metadata.get('bbox_tolerance_mm', 3.0)

    score = 0
    feedback_parts = []
    
    # 2. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate File & Timestamp (30 pts)
    file_exists = result.get('file_exists', False)
    created_during = result.get('file_created_during_task', False)
    valid_doc = result.get('geometry', {}).get('valid_doc', False)

    if file_exists and valid_doc:
        score += 15
        feedback_parts.append("Valid FreeCAD file exists")
        if created_during:
            score += 15
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File timestamp predates task (Anti-gaming check failed)")
    else:
        feedback_parts.append("Output file missing or invalid")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 4. Evaluate Geometry (50 pts)
    geo = result.get('geometry', {})
    
    # Volume Check (20 pts)
    actual_vol = geo.get('max_volume', 0.0)
    if abs(actual_vol - expected_vol) <= vol_tol:
        score += 20
        feedback_parts.append(f"Volume correct ({actual_vol:.1f} mm³)")
    else:
        feedback_parts.append(f"Volume incorrect ({actual_vol:.1f} vs ~{expected_vol})")

    # BBox Check (15 pts)
    actual_bbox = geo.get('bbox', [0, 0, 0]) # These are already sorted from export script
    bbox_ok = True
    for a, e in zip(actual_bbox, expected_bbox):
        if abs(a - e) > bbox_tol:
            bbox_ok = False
            break
            
    if bbox_ok:
        score += 15
        feedback_parts.append("Dimensions correct")
    elif actual_bbox[2] > 50 and actual_bbox[2] < 70: # Partial credit for correct height
        score += 5
        feedback_parts.append("Height roughly correct, diameter wrong")
    else:
        feedback_parts.append(f"Dimensions wrong ({actual_bbox})")

    # Feature Check (15 pts)
    if geo.get('has_revolution', False):
        score += 15
        feedback_parts.append("Revolution features detected")
    else:
        feedback_parts.append("No revolution geometry found")

    # 5. VLM Verification (20 pts)
    # Check if we see the Sketcher or Revolution tool usage in trajectory
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = """
        Review these screenshots of a user working in FreeCAD.
        Check for the following:
        1. Is there a sketch being drawn (lines on a grid)?
        2. Is there a "Revolution" or "Revolve" operation being set up (yellow revolution shape preview)?
        3. Does the final shape look like a stepped cylinder/shaft?
        
        Answer JSON: {"sketch_visible": bool, "revolution_tool_visible": bool, "final_shape_correct": bool}
        """
        
        try:
            vlm_out = query_vlm(prompt=vlm_prompt, images=frames + [final_img])
            parsed = vlm_out.get('parsed', {})
            
            vlm_score = 0
            if parsed.get('sketch_visible'): vlm_score += 5
            if parsed.get('revolution_tool_visible'): vlm_score += 5
            if parsed.get('final_shape_correct'): vlm_score += 10
            
            score += vlm_score
            feedback_parts.append(f"Visual verification: {vlm_score}/20")
            
        except Exception:
            # Fallback if VLM fails, grant partial points if geometry is perfect
            if score >= 70:
                score += 20
                feedback_parts.append("VLM skipped (Geometry perfect)")
    else:
        feedback_parts.append("No trajectory frames for visual verification")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }