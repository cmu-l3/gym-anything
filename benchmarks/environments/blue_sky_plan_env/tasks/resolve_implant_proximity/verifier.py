#!/usr/bin/env python3
"""
Verifier for resolve_implant_proximity task.

Task: Move Implant #31 to achieve >= 3.0mm spacing from Implant #30.

Verification Strategy:
1. File Verification: Check if `resolved_case.bsp` exists and was modified.
2. VLM Verification: Analyze trajectory/final screenshot to confirm:
   - Measurement tool is visible.
   - Measured distance is >= 3.0mm.
   - Implants are still in the bone (context check).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a dental implant planning task.
The goal was to move the right-most implant (Implant #31) to increase the gap between it and the adjacent implant (Implant #30) to at least 3.0 mm.

Review the screenshots. Look for:
1. Two dental implants (screw-shaped objects) visible in the bone.
2. A measurement line or ruler between them.
3. A numeric value indicating the distance (e.g., "3.0 mm", "3.2 mm", "4.1 mm").
4. Verify the implants are still embedded in the bone (not floating in air or colliding).

JSON Response format:
{
    "measurement_visible": true/false,
    "measured_value_mm": float or null,
    "implants_in_bone": true/false,
    "gap_appears_sufficient": true/false,
    "reasoning": "text"
}
"""

def verify_resolve_implant_proximity(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the implant proximity resolution task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows env, copy_from_env handles the path conversion usually
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Basic Scoring Criteria
    score = 0
    feedback_parts = []
    
    # Criterion A: Output File Exists (20 pts)
    if result_data.get('output_exists', False):
        score += 20
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file NOT saved.")

    # Criterion B: File Modified During Task (20 pts)
    if result_data.get('file_created_during_task', False):
        score += 20
        feedback_parts.append("Project file modified during task.")
    else:
        feedback_parts.append("Project file not modified.")

    # Criterion C: App Running (10 pts)
    if result_data.get('app_was_running', False):
        score += 10
    
    # 3. VLM Verification (50 pts)
    # We check the final state and a few frames back to find the measurement
    frames = sample_trajectory_frames(traj, n=3)
    final_shot = get_final_screenshot(traj)
    
    # Add final shot to analysis list
    if final_shot:
        frames.append(final_shot)
    
    if not frames:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    # Query VLM
    vlm_result = query_vlm(
        prompt=VLM_PROMPT,
        images=frames,
        model="gpt-4o" # or equivalent high-capability model
    )
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Check measurement visibility
        if parsed.get("measurement_visible"):
            vlm_score += 10
            feedback_parts.append("Measurement tool visible.")
            
            # Check value
            val = parsed.get("measured_value_mm")
            if val is not None and isinstance(val, (int, float)):
                if val >= 3.0:
                    vlm_score += 30
                    feedback_parts.append(f"Gap measured at {val}mm (Success).")
                else:
                    feedback_parts.append(f"Gap measured at {val}mm (Too small, target >= 3.0mm).")
            elif parsed.get("gap_appears_sufficient"):
                # Fallback if OCR fails but visual looks good
                vlm_score += 20
                feedback_parts.append("Gap appears sufficient visually.")
        else:
            feedback_parts.append("No measurement tool visible in screenshots.")

        # Check safety (implants in bone)
        if parsed.get("implants_in_bone"):
            vlm_score += 10
        else:
            feedback_parts.append("Warning: Implants may be positioned outside bone.")
            
    else:
        feedback_parts.append("VLM analysis failed.")

    score += vlm_score

    # 4. Final Assessment
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }