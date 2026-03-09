#!/usr/bin/env python3
"""
Verifier for measure_3d_zygomatic_width task.

Criteria:
1. Project file created during task.
2. 3D Surface exists (Prerequisite for 3D measurement).
3. At least one measurement exists.
4. Measurement value is within 110-160mm (Typical Bizygomatic width).
5. VLM confirms 3D skull and measurement line visibility.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_measure_3d_zygomatic_width(traj, env_info, task_info):
    """Verify 3D skull measurement task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_width = metadata.get("min_width_mm", 110.0)
    max_width = metadata.get("max_width_mm", 160.0)

    score = 0
    feedback_parts = []
    
    # --- Step 1: Programmatic Verification ---
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {e}"
        }

    # Criterion 1: Project Exists (20 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Project file saved")
    else:
        feedback_parts.append("Project file not saved or not new")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: 3D Surface Generated (30 pts)
    if result.get("has_surface"):
        score += 30
        feedback_parts.append("3D surface generated")
    else:
        feedback_parts.append("No 3D surface found in project")

    # Criterion 3: Measurement Exists & Value Check (30 pts)
    measurements = result.get("measurements", [])
    valid_measurement = False
    best_val = 0
    
    if len(measurements) > 0:
        # Check for any measurement in the plausible range
        for m in measurements:
            val = m.get("value_mm", 0)
            if min_width <= val <= max_width:
                valid_measurement = True
                best_val = val
                break
        
        if valid_measurement:
            score += 30
            feedback_parts.append(f"Valid facial width measurement found ({best_val:.1f} mm)")
        else:
            vals = [f"{m.get('value_mm',0):.1f}" for m in measurements]
            feedback_parts.append(f"Measurements found but out of range {min_width}-{max_width}mm: {vals}")
            # Partial credit for having *any* measurement
            score += 10 
    else:
        feedback_parts.append("No measurements found in project")

    # --- Step 2: VLM Verification (20 pts) ---
    # Use trajectory to confirm they actually interacted with 3D view
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot and valid_measurement: # Only run VLM if data looks promising to save cost/time
        prompt = """
        You are verifying a medical software task.
        Goal: Measure the width of the face (cheekbone to cheekbone) on a 3D skull model.
        
        Look at the screenshot:
        1. Is a 3D skull model visible? (Not just 2D slices)
        2. Is there a measurement line or text visible in the 3D view?
        3. Does the measurement appear to span the width of the face (zygomatic arches)?
        
        Return JSON: {"3d_skull_visible": bool, "measurement_visible": bool, "correct_placement": bool}
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("3d_skull_visible"):
                score += 10
                feedback_parts.append("VLM confirmed 3D skull")
            if parsed.get("measurement_visible"):
                score += 10
                feedback_parts.append("VLM confirmed measurement line")
    elif final_screenshot:
        # If programmatic check failed but file exists, give VLM a chance to catch UI interaction
        pass

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }