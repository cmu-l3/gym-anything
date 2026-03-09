#!/usr/bin/env python3
"""
Verifier for model_turbine_blade task.

Checks:
1. File existence and creation time.
2. Geometric properties extracted via FreeCAD API:
   - Height (Z-length)
   - Volume
   - Bounding Box Dimensions (to verify twist)
3. VLM visual confirmation.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_turbine_blade(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_height = metadata.get('expected_height_mm', 100.0)
    height_tolerance = metadata.get('height_tolerance_mm', 1.0)
    expected_volume = metadata.get('expected_volume_mm3', 5800.0)
    volume_tolerance = metadata.get('volume_tolerance_mm3', 600.0)
    min_y_for_twist = metadata.get('min_y_width_for_twist_mm', 14.0)

    # Copy result JSON
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
    
    # 1. File Existence & Validity (20 pts)
    if result.get('file_exists'):
        if result.get('file_created_during_task'):
            score += 10
            feedback_parts.append("File created")
        else:
            feedback_parts.append("File exists but old")
            
        if result.get('is_valid_doc'):
            score += 10
        else:
            feedback_parts.append("Invalid FCStd file")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Geometric Verification (60 pts)
    if result.get('has_solid'):
        score += 10
        
        # Height Check (20 pts)
        height = result.get('solid_height', 0)
        if abs(height - expected_height) <= height_tolerance:
            score += 20
            feedback_parts.append(f"Height correct ({height:.1f}mm)")
        else:
            feedback_parts.append(f"Height incorrect ({height:.1f}mm)")

        # Volume Check (15 pts)
        volume = result.get('solid_volume', 0)
        if abs(volume - expected_volume) <= volume_tolerance:
            score += 15
            feedback_parts.append(f"Volume correct ({volume:.0f}mm³)")
        else:
            feedback_parts.append(f"Volume mismatch ({volume:.0f}mm³)")

        # Twist Verification (15 pts)
        # Root is 20x6 (Y-width 12mm). Tip is 12x3.
        # If tip is rotated 45 deg, the bounding box Y-width expands significantly.
        # Theoretical projection ~21mm. Threshold set to 14mm.
        y_width = result.get('bbox_y_width', 0)
        if y_width > min_y_for_twist:
            score += 15
            feedback_parts.append("Twist verified (Bounding Box check)")
        else:
            feedback_parts.append(f"Twist likely missing (Y-width {y_width:.1f}mm)")
            
    else:
        feedback_parts.append("No solid body found in document")

    # 3. VLM Verification (20 pts)
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        vlm_prompt = (
            "Review these screenshots of a FreeCAD task.\n"
            "The goal is to create a 3D twisted turbine blade using a Loft operation.\n"
            "1. Do you see two elliptical sketches at different heights?\n"
            "2. Is the top sketch rotated relative to the bottom one (twisted)?\n"
            "3. Is there a final solid 3D shape visible?\n"
            "Reply with JSON: {\"sketches_visible\": bool, \"twist_visible\": bool, \"solid_visible\": bool}"
        )
        
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('solid_visible'):
                score += 10
            if parsed.get('twist_visible'):
                score += 10
            feedback_parts.append("Visual verification completed")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }